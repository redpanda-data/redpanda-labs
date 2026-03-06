# Redpanda AI Gateway Agent

A LangGraph ReAct agent that connects to the [Redpanda AI Gateway](https://ai-gateway.d6b2mdhdvf8ruqkbl2mg.clusters.rdpa.co)
for unified LLM access and MCP tool calling, with optional LangSmith tracing.

## About the gateway

The [Redpanda AI Gateway](https://ai-gateway.d6b2mdhdvf8ruqkbl2mg.clusters.rdpa.co) is a **multi-tenant** platform
where each user configures their own gateway instance. This project uses the gateway at:

```
https://ai-gateway.d6b2mdhdvf8ruqkbl2mg.clusters.rdpa.co/.redpanda/gateways/d6b3mk93mouc73cortj0
```

This particular gateway is configured with **OpenAI-compatible API format** but
routes to **Google Gemini** as the model provider behind the scenes. The gateway
handles all provider-specific auth and request translation — clients only see
a standard OpenAI chat completions interface.

Other users may configure their gateways differently (different providers,
models, MCP tools, auth settings). The gateway ID (`d6b3mk93mouc73cortj0`)
is sent via the `rp-aigw-id` header to route requests to the correct instance.

## Prerequisites

- **Python 3.12+**
- **[Poetry](https://python-poetry.org/)** for dependency management
- **Redpanda AI Gateway** credentials:
  - A **service account** created in [Redpanda Cloud](https://cloud.redpanda.com) with permissions to the specific cluster (provides the OIDC client ID and secret)
  - Gateway ID (`rp-aigw-id` header value)
- **LangSmith** API key (optional, for tracing)

## Quick start

```bash
# Install dependencies
poetry install

# Configure credentials
cp .env.example .env.local
# Edit .env.local with your REDPANDA_CLIENT_ID and REDPANDA_CLIENT_SECRET

# Run the agent
poetry run redpanda-agent
```

## Architecture

```
[Python Agent (LangGraph)]
    |
    |-- OIDC client_credentials flow (authlib) --> Redpanda Cloud IdP --> Bearer token
    |
    |-- ChatOpenAI(base_url="https://ai-gateway.d6b2mdhdvf8ruqkbl2mg.clusters.rdpa.co/v1", ...)
    |       |
    |       +-- OpenAI-compatible API via gateway (any upstream provider)
    |
    |-- MCP Tools via gateway (https://ai-gateway.d6b2mdhdvf8ruqkbl2mg.clusters.rdpa.co/mcp/)
    |       |
    |       +-- tool_search      --> discovers available tools dynamically
    |       +-- AgentMiddleware  --> injects & executes discovered tools at runtime
    |
    |-- LangSmith tracing (env vars: LANGSMITH_API_KEY, LANGSMITH_PROJECT)
```

## Project structure

```
src/agent/
    __init__.py
    auth.py      # OIDC token management (authlib, client_credentials)
    gateway.py   # ChatOpenAI configured for the gateway
    tools.py     # MCP tool loading + AgentMiddleware for dynamic discovery
    sprite.py    # 8-bit red panda pixel art
    graph.py     # LangGraph agent graph (create_agent + middleware)
    main.py      # TUI entry point (Textual)
```

---

## Gateway integration notes

> Gotchas and design decisions for integrating LangChain/LangGraph with the
> Redpanda AI Gateway.

### This gateway returns OpenAI-format responses

This gateway instance is configured with OpenAI compatibility enabled. It
translates upstream provider responses (Google Gemini in our case) into the
**OpenAI chat completions** format (`choices`, `chat.completion`, etc.).
This is a **per-gateway configuration** — other gateways on the platform may
behave differently depending on how their owner configured them.

```json
{
  "id": "msg_...",
  "object": "chat.completion",
  "choices": [{ "message": { "content": "...", "role": "assistant" } }]
}
```

**Implication:** Use `ChatOpenAI` (from `langchain-openai`), **not**
`ChatAnthropic` (or any provider-specific client). Point it at `{gateway_url}/v1`:

```python
from langchain_openai import ChatOpenAI

llm = ChatOpenAI(
    base_url="https://ai-gateway.d6b2mdhdvf8ruqkbl2mg.clusters.rdpa.co/v1",
    api_key="not-used",  # auth is via OIDC Bearer token
    model="google/gemini-3-flash-preview",
    default_headers={
        "Authorization": f"Bearer {token}",
        "rp-aigw-id": gateway_id,
    },
)
```

### OIDC authentication

Authentication is against the **Redpanda Cloud OIDC identity provider**, not
the gateway itself. The gateway validates the resulting tokens.

The `GatewayAuth` class uses **OIDC discovery** to resolve the token endpoint
automatically from the issuer (`https://auth.prd.cloud.redpanda.com`):

```
https://auth.prd.cloud.redpanda.com/.well-known/openid-configuration
```

It fetches this discovery document on the first token request, then uses a
`client_credentials` grant with the audience `cloudv2-production.redpanda.cloud`:

```python
auth = GatewayAuth()  # uses REDPANDA_ISSUER env var or default
token = await auth.get_token()
```

> **Note:** The AI agent is responsible for refreshing tokens before they expire.
> `GatewayAuth` handles this automatically with a 30-second buffer.

### Every request needs two headers

| Header          | Value                   | Purpose                    |
|-----------------|-------------------------|----------------------------|
| `Authorization` | `Bearer <oidc_token>`   | OIDC authentication        |
| `rp-aigw-id`    | `d6b3mk93mouc73cortj0`  | Identifies the gateway instance |

Both must be on **every** request — LLM calls and MCP calls.

### MCP: two-level dynamic tool discovery

The gateway's MCP endpoint (`/mcp/`) uses a **meta-tool pattern**:

1. `list_tools()` returns a small set of static tools — **`tool_search`** plus
   tools from the `mcp_orchestrator_d6b3mk93mouc73cortj0` server for programmatic
   tool calling
2. Calling `tool_search` discovers *additional* tools available on the gateway
   (e.g. `redpanda-docs:ask_redpanda_question`)
3. The set of discovered tools **can change at any time** — they are not static

#### `AgentMiddleware` for dynamic tool injection

Because tools are dynamically discovered, we use LangChain 1.0's
`AgentMiddleware` to inject them at runtime. A custom `MCPGatewayMiddleware`
provides two hooks:

- **`awrap_model_call`** — injects dynamically discovered tools into the
  model's tool list before each LLM call
- **`awrap_tool_call`** — intercepts calls to discovered tools and executes
  them via the raw MCP `ClientSession.call_tool()` (which has no client-side
  validation and accepts any tool name)

When `tool_search` returns results, the middleware parses them and registers
`StructuredTool` wrappers. These appear as normal tools to the LLM on
subsequent turns.

```python
from langchain.agents import create_agent

graph = create_agent(
    model=llm,
    tools=static_tools,       # e.g. [tool_search]
    middleware=[middleware],   # MCPGatewayMiddleware
)
```

The agent's workflow becomes:
1. **`tool_search`** — discover available tools (middleware caches them)
2. **`redpanda-docs-ask_redpanda_question(...)`** — call discovered tools
   directly by name (middleware routes to MCP session)

See the [LangChain forum discussion](https://forum.langchain.com/t/are-dynamic-tool-lists-allowed-when-using-create-agent/1920)
for background on this pattern.

#### Tool name sanitization

The OpenAI API requires tool names to match `^[a-zA-Z0-9_-]{1,128}$`. MCP
tool names like `redpanda-docs:ask_redpanda_question` contain colons. The
middleware sanitizes names (replacing invalid characters with `-`) and
maintains a mapping back to the original MCP name for execution.

#### Why not pre-discover at startup?

The tool set is dynamic — tools can be added, removed, or renamed on the
gateway without restarting the agent. Pre-discovering and hard-coding tool
definitions at startup would go stale.

### MCP transport

Use `streamable_http` (not `sse` or `stdio`):

```python
client = MultiServerMCPClient({
    "gateway": {
        "transport": "streamable_http",
        "url": "https://ai-gateway.d6b2mdhdvf8ruqkbl2mg.clusters.rdpa.co/mcp/",
        "headers": { ... },
    },
})
```

### LangSmith tracing

Zero-code — just set environment variables:

```bash
LANGSMITH_API_KEY=<key>
LANGSMITH_PROJECT=redpanda-agent
LANGSMITH_TRACING=true
```

LangChain/LangGraph auto-detect these and trace all LLM + tool calls.

### Dependency notes

| Package                    | Why                                          |
|----------------------------|----------------------------------------------|
| `langchain-openai`         | Gateway speaks OpenAI format regardless of upstream provider |
| `langchain-mcp-adapters`   | MCP client + tool conversion (static tools)   |
| `authlib`                  | OIDC `client_credentials` with token caching  |

The gateway handles upstream auth injection — you never set provider API keys directly.
