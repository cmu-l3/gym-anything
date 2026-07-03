"""Shared 'drivable agent' seam.

An agent that mixes this in can be driven by an external loop that OWNS the
model call — e.g. a prime-rl trainer serving the policy over an
OpenAI-compatible endpoint and sampling itself. The loop reuses the agent's
own decision logic: its system prompt (`get_system_prompt`) and its response
parser (`parse_qwen3vl_response`), building the prompt and parsing the
completion, while doing the sampling in between. The agent's local `step()`
is unaffected, and this is ONE definition shared by every OpenAI-compatible
agent, so selecting an agent under prime-rl mirrors `--agent` locally.

Provider-native agents (Anthropic/Google/Azure native tools) do not mix this
in: their model call cannot be served over an OpenAI policy endpoint.
"""

from __future__ import annotations

from typing import Any, Dict, Optional, Tuple

from agents.shared.qwen_computer_use import INSTRUCTION_TEMPLATE, parse_qwen3vl_response


def _completion_text(completion) -> str:
    """Best-effort extraction of assistant text from a chat message object/dict."""
    content = getattr(completion, "content", None)
    if content is None and isinstance(completion, dict):
        content = completion.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "".join(
            part.get("text", "") for part in content if isinstance(part, dict) and part.get("type") == "text"
        )
    return str(content or "")


class DrivableAgentMixin:
    """Exposes an agent's request-building and parsing to an external driver."""

    driven = True
    # Coordinate scaling passed to the parser, matching what this agent's own
    # step() uses. None = the parser default (0-1000 normalized -> 1920x1080).
    _driver_parse_ratio: Optional[Tuple[float, float]] = None

    def driver_initial_messages(self, screenshot_b64: str):
        """Opening messages: the agent's system prompt + first screenshot."""
        return [
            {"role": "system", "content": [{"type": "text", "text": self.get_system_prompt()}]},
            {
                "role": "user",
                "content": [
                    {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{screenshot_b64}"}},
                    {"type": "text", "text": INSTRUCTION_TEMPLATE.format(instruction=self.task_description)},
                ],
            },
        ]

    def driver_observation_messages(self, screenshot_b64: str):
        """A subsequent turn: the new screenshot only."""
        return [
            {
                "role": "user",
                "content": [{"type": "image_url", "image_url": {"url": f"data:image/png;base64,{screenshot_b64}"}}],
            }
        ]

    def driver_parse(self, completion) -> Dict[str, Any]:
        """Parse a raw model completion into env action groups + control flags.

        Uses the exact parser (and coordinate scaling) this agent's step()
        uses, so a driven rollout and a local rollout decide identically.
        """
        text = completion if isinstance(completion, str) else _completion_text(completion)
        kwargs = {"scale_dims_ratio": self._driver_parse_ratio} if self._driver_parse_ratio else {}
        parsed = parse_qwen3vl_response(text, **kwargs)
        md = parsed["metadata"]
        if md.get("is_terminal"):
            self.done = True
        return {
            "actions": parsed["actions"],
            "done": bool(md.get("is_terminal")),
            "wait": md.get("wait_time"),
            "parse_error": bool(md.get("parse_error")),
        }


__all__ = ["DrivableAgentMixin"]
