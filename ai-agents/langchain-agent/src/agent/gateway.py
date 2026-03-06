"""LLM client configured for the Redpanda AI Gateway."""

import os

from langchain_openai import ChatOpenAI

from agent.auth import GatewayAuth


async def create_llm(auth: GatewayAuth) -> ChatOpenAI:
    """Create a ChatOpenAI instance routed through the Redpanda AI Gateway.

    The gateway returns OpenAI-compatible responses regardless of upstream provider.
    """
    headers = await auth.get_headers()
    model = os.environ.get("REDPANDA_MODEL", "google/gemini-3-flash-preview")

    return ChatOpenAI(
        base_url=f"{auth.gateway_url}/v1",
        api_key="not-used",
        model=model,
        default_headers=headers,
    )
