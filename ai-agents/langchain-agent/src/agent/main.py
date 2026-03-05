"""TUI entry point for the Redpanda agent."""

import asyncio
from typing import ClassVar

from dotenv import load_dotenv
from langchain_core.messages import AnyMessage, HumanMessage
from textual import work
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import VerticalScroll
from textual.timer import Timer
from textual.widgets import Input, Markdown, Static

from agent.auth import GatewayAuth
from agent.gateway import create_llm
from agent.graph import build_graph
from agent.sprite import SPRITE
from agent.tools import load_mcp_tools

SPINNER_FRAMES = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
STATUS_ID = "status-msg"


class ChatMessage(Markdown):
    """A single chat message."""

    def __init__(self, role: str, content: str) -> None:
        super().__init__(content)
        self.add_class(role)


class RedpandaAgentApp(App[None]):
    """Redpanda Agent TUI."""

    CSS = """
    Screen {
        background: #111111;
    }
    #banner {
        width: 100%;
        content-align: center middle;
        text-align: center;
        padding: 2 0 0 0;
    }
    #title-text {
        width: 100%;
        content-align: center middle;
        text-align: center;
        color: #666666;
        padding: 0 0 1 0;
    }
    #chat-scroll {
        height: 1fr;
        padding: 0 4;
    }
    .user {
        margin: 1 0 0 12;
        padding: 1 2;
        background: #1a1a2e;
        color: #e0e0e0;
    }
    .assistant {
        margin: 0 12 1 0;
        padding: 1 2;
        background: #1a1a1a;
        color: #cccccc;
    }
    .status {
        margin: 0 12 0 0;
        padding: 0 2;
        color: #cc2200;
    }
    #input {
        dock: bottom;
        margin: 1 4;
        background: #1a1a1a;
        border: tall #333333;
        color: #e0e0e0;
    }
    #input:focus {
        border: tall #cc0000;
    }
    """

    TITLE = "Redpanda Agent"
    BINDINGS: ClassVar[list[Binding]] = [
        Binding("ctrl+c", "quit", "Quit", show=False),
    ]

    def __init__(self) -> None:
        super().__init__()
        self._auth: GatewayAuth | None = None
        self._graph = None
        self._messages: list[AnyMessage] = []
        self._agent_ready = False
        self._spinner_timer: Timer | None = None
        self._spinner_frame = 0
        self._status_text = ""

    def compose(self) -> ComposeResult:
        """Build the UI layout."""
        yield Static(SPRITE, id="banner", markup=True)
        yield Static("redpanda agent", id="title-text")
        yield VerticalScroll(id="chat-scroll")
        yield Input(placeholder="", disabled=True, id="input")

    def _tick_spinner(self) -> None:
        """Advance the spinner animation one frame."""
        scroll = self.query_one("#chat-scroll", VerticalScroll)
        existing = scroll.query(f"#{STATUS_ID}")
        if existing:
            frame = SPINNER_FRAMES[self._spinner_frame % len(SPINNER_FRAMES)]
            existing.first().update(f"{frame} {self._status_text}")
            self._spinner_frame += 1

    async def _set_status(self, text: str) -> None:
        """Show an animated spinner with a status message in the chat."""
        self._status_text = text
        self._spinner_frame = 0
        frame = SPINNER_FRAMES[0]

        scroll = self.query_one("#chat-scroll", VerticalScroll)
        existing = scroll.query(f"#{STATUS_ID}")
        if existing:
            existing.first().update(f"{frame} {text}")
        else:
            widget = Static(f"{frame} {text}", id=STATUS_ID)
            widget.add_class("status")
            await scroll.mount(widget)
        scroll.scroll_end(animate=False)

        if not self._spinner_timer:
            self._spinner_timer = self.set_interval(0.08, self._tick_spinner)

    async def _clear_status(self) -> None:
        """Stop the spinner and remove the status message."""
        if self._spinner_timer:
            self._spinner_timer.stop()
            self._spinner_timer = None

        scroll = self.query_one("#chat-scroll", VerticalScroll)
        existing = scroll.query(f"#{STATUS_ID}")
        if existing:
            await existing.first().remove()

    async def on_mount(self) -> None:
        """Initialize the agent after the app mounts."""
        self._init_agent()

    @work(thread=False)
    async def _init_agent(self) -> None:
        """Connect to the gateway and build the agent graph."""
        load_dotenv()
        input_w = self.query_one("#input", Input)

        await self._set_status("connecting...")
        self._auth = GatewayAuth()

        llm, (tools, _mcp_client, middleware) = await asyncio.gather(
            create_llm(self._auth),
            load_mcp_tools(self._auth),
        )

        self._graph = build_graph(llm, tools, middleware=[middleware])
        self._agent_ready = True

        await self._clear_status()
        tool_names = ", ".join(t.name for t in tools)
        scroll = self.query_one("#chat-scroll", VerticalScroll)
        await scroll.mount(
            ChatMessage("assistant", f"Ready. {len(tools)} tools loaded: {tool_names}")
        )
        scroll.scroll_end(animate=False)

        input_w.placeholder = "ask anything about redpanda..."
        input_w.disabled = False
        input_w.focus()

    async def on_input_submitted(self, event: Input.Submitted) -> None:
        """Handle user message submission."""
        text = event.value.strip()
        if not text or not self._agent_ready:
            return

        event.input.value = ""
        event.input.disabled = True

        scroll = self.query_one("#chat-scroll", VerticalScroll)
        await scroll.mount(ChatMessage("user", text))
        scroll.scroll_end(animate=False)

        await self._set_status("thinking...")
        self._send_message(text)

    @work(thread=False)
    async def _send_message(self, text: str) -> None:
        """Send a message to the agent and display the response."""
        scroll = self.query_one("#chat-scroll", VerticalScroll)
        input_w = self.query_one("#input", Input)

        self._messages.append(HumanMessage(content=text))
        result = await self._graph.ainvoke({"messages": self._messages})
        self._messages = result["messages"]

        await self._clear_status()

        assistant_msg = self._messages[-1]
        await scroll.mount(
            ChatMessage("assistant", str(assistant_msg.content))
        )
        scroll.scroll_end(animate=False)

        input_w.disabled = False
        input_w.focus()

    async def action_quit(self) -> None:
        """Clean up and quit."""
        if self._auth:
            await self._auth.close()
        self.exit()


def main() -> None:
    """Launch the TUI."""
    RedpandaAgentApp().run()


if __name__ == "__main__":
    main()
