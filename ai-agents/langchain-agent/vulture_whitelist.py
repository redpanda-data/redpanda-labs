# Vulture whitelist — framework-invoked methods and class attributes.
# These are called by Textual / LangChain at runtime, not directly.

from agent.main import RedpandaAgentApp  # noqa: F401
from agent.tools import MCPGatewayMiddleware  # noqa: F401

# Textual framework hooks
RedpandaAgentApp.CSS
RedpandaAgentApp.TITLE
RedpandaAgentApp.BINDINGS
RedpandaAgentApp.compose
RedpandaAgentApp.on_mount
RedpandaAgentApp.on_input_submitted
RedpandaAgentApp.action_quit

# LangChain AgentMiddleware overrides
MCPGatewayMiddleware.awrap_model_call
MCPGatewayMiddleware.awrap_tool_call
