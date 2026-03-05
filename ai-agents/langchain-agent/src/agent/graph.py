"""LangGraph agent definition using create_agent with middleware."""

from collections.abc import Sequence

from langchain.agents import create_agent
from langchain.agents.middleware import AgentMiddleware
from langchain_core.language_models import BaseChatModel
from langchain_core.tools import BaseTool
from langgraph.graph.state import CompiledStateGraph

SYSTEM_PROMPT = (
    "You are a helpful Redpanda assistant. You answer questions about Redpanda — its "
    "architecture, configuration, topic management, connectors, and more.\n\n"
    "You have a `tool_search` tool that discovers documentation tools on the gateway. "
    "Call it first to find tools by keyword (e.g. 'redpanda', 'docs'), then call the "
    "discovered tools directly by name.\n\n"
    "When you use a tool, cite the relevant documentation in your answer."
)


def build_graph(
    llm: BaseChatModel,
    tools: list[BaseTool],
    middleware: Sequence[AgentMiddleware[object, None, object]] | None = None,
) -> CompiledStateGraph:  # type: ignore[type-arg]
    """Build and compile the agent graph with optional middleware."""
    return create_agent(
        model=llm,
        tools=tools,
        system_prompt=SYSTEM_PROMPT,
        middleware=middleware or [],
    )
