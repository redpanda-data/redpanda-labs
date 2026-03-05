"""MCP tool loading and dynamic discovery middleware for the Redpanda AI Gateway.

The gateway uses a two-level discovery pattern:
1. `list_tools()` returns a `tool_search` meta-tool
2. Calling `tool_search` discovers actual tools (e.g. `redpanda-docs:ask_redpanda_question`)
3. Discovered tools can change at any time — they are NOT static

We use `AgentMiddleware` with `awrap_model_call` and `awrap_tool_call` to dynamically
inject tools discovered via `tool_search` into the agent's tool set at runtime.
"""

import json
import re
from collections.abc import Awaitable, Callable

from langchain.agents.middleware import (
    AgentMiddleware,
    ModelRequest,
    ModelResponse,
    ToolCallRequest,
)
from langchain_core.messages import ToolMessage
from langchain_core.tools import BaseTool, StructuredTool
from langchain_mcp_adapters.client import MultiServerMCPClient
from langgraph.types import Command
from pydantic import create_model

from agent.auth import GatewayAuth

# Type aliases for middleware handler signatures
ModelHandler = Callable[[ModelRequest[None]], Awaitable[ModelResponse[None]]]
ToolHandler = Callable[[ToolCallRequest], Awaitable[ToolMessage | Command[str]]]

MCP_SESSION_KEY = "gateway"
TOOL_SEARCH_NAME = "tool_search"


class MCPGatewayMiddleware(AgentMiddleware):  # type: ignore[type-arg]
    """Middleware that discovers MCP tools at runtime and injects them into the agent."""

    def __init__(self, client: MultiServerMCPClient) -> None:
        self._client = client
        self._discovered: dict[str, StructuredTool] = {}
        self._name_map: dict[str, str] = {}  # sanitized name -> original MCP name

    async def awrap_model_call(
        self,
        request: ModelRequest[None],
        handler: ModelHandler,
    ) -> ModelResponse[None]:
        """Inject dynamically discovered tools into the model's tool list."""
        if self._discovered:
            extra = list(self._discovered.values())
            return await handler(
                request.override(tools=[*(request.tools or []), *extra])
            )
        return await handler(request)

    async def awrap_tool_call(
        self,
        request: ToolCallRequest,
        handler: ToolHandler,
    ) -> ToolMessage | Command[str]:
        """Handle calls to dynamically discovered tools via MCP session."""
        tool_name = request.tool_call["name"]

        # If it's a statically registered tool (e.g. tool_search), let it through.
        # When tool_search returns results, cache the discovered tools.
        if tool_name not in self._discovered:
            result = await handler(request)
            if tool_name == TOOL_SEARCH_NAME and isinstance(result, ToolMessage):
                self._register_discovered_tools(result.content)
            return result

        # Execute dynamically discovered tool via raw MCP session
        mcp_name = self._name_map.get(tool_name, tool_name)
        args = request.tool_call.get("args", {})
        async with self._client.session(MCP_SESSION_KEY) as session:
            mcp_result = await session.call_tool(mcp_name, args)

        parts = []
        for block in mcp_result.content:
            if hasattr(block, "text"):
                parts.append(block.text)
            else:
                parts.append(json.dumps(block.model_dump(), default=str))

        content = "\n".join(parts)
        if mcp_result.isError:
            content = f"Error: {content}"

        return ToolMessage(
            content=content,
            tool_call_id=request.tool_call["id"],
        )

    def _register_discovered_tools(self, content: str | list[dict[str, str]]) -> None:
        """Parse tool_search output and register discovered tools."""
        if isinstance(content, list):
            text = next(
                (
                    b["text"] if isinstance(b, dict) else getattr(b, "text", "")
                    for b in content
                    if (isinstance(b, dict) and b.get("type") == "text")
                    or getattr(b, "type", None) == "text"
                ),
                "",
            )
        else:
            text = content

        try:
            data = json.loads(text)
        except (json.JSONDecodeError, TypeError):
            return

        for tool_def in data.get("tools", []):
            original_name = tool_def.get("name", "")
            if not original_name:
                continue
            safe_name = _sanitize_tool_name(original_name)
            if safe_name in self._discovered:
                continue
            self._name_map[safe_name] = original_name
            schema = tool_def.get("inputSchema", {})
            fields = _schema_to_fields(schema)
            input_model = create_model(f"{safe_name}_Input", **fields)
            self._discovered[safe_name] = StructuredTool.from_function(
                func=lambda **_kw: "",
                coroutine=lambda **_kw: "",
                name=safe_name,
                description=tool_def.get("description", original_name),
                args_schema=input_model,
            )


def _sanitize_tool_name(name: str) -> str:
    """Sanitize an MCP tool name to match OpenAI's ``^[a-zA-Z0-9_-]{1,128}$`` pattern."""
    safe = re.sub(r"[^a-zA-Z0-9_-]", "-", name)
    return safe[:128]


def _schema_to_fields(
    schema: dict[str, dict[str, str | dict[str, str]]],
) -> dict[str, tuple[type, str | None | type[...]]]:
    """Convert a JSON Schema properties dict to pydantic create_model fields."""
    type_map: dict[str, type] = {
        "string": str,
        "integer": int,
        "number": float,
        "boolean": bool,
    }
    fields: dict[str, tuple[type, str | None | type[...]]] = {}
    required = set(schema.get("required", []))
    for prop_name, prop_def in schema.get("properties", {}).items():
        py_type = type_map.get(str(prop_def.get("type", "string")), str)
        default: str | None | type[...] = ... if prop_name in required else prop_def.get("default")
        fields[prop_name] = (py_type, default)
    return fields


async def load_mcp_tools(
    auth: GatewayAuth,
) -> tuple[list[BaseTool], MultiServerMCPClient, MCPGatewayMiddleware]:
    """Connect to the gateway MCP endpoint and return tools + middleware.

    Returns the static tools (e.g. tool_search), the MCP client, and the
    middleware that handles dynamic tool discovery at runtime.
    """
    headers = await auth.get_headers()

    client = MultiServerMCPClient(
        {
            MCP_SESSION_KEY: {
                "transport": "streamable_http",
                "url": f"{auth.gateway_url}/mcp/",
                "headers": headers,
            },
        }
    )
    static_tools = await client.get_tools()
    middleware = MCPGatewayMiddleware(client)

    return static_tools, client, middleware
