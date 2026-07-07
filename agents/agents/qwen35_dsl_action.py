"""
Qwen35DSLActionAgent — same CUA-DSL grammar as Qwen35DSLAgent, but each
assistant turn is two lines instead of one:

    Action: <one short imperative describing the UI step>
    >> <one or more DSL commands>

The rationale line is optional at generation time (the model may emit just
`>>`) and is fully ignored by the action dispatcher — `Qwen35DSLAgent`'s
parser uses `re.MULTILINE` to find the first `>>` line and treats anything
above it as prose. This subclass overrides only:

  * `_system_prompt` — documents the two-line format. Required because the
    training-data system prompt for the Action+DSL variant differs from the
    pure-DSL agent's prompt; a model trained on one and prompted with the
    other gets a contradictory signal.
  * `_parse_response` — copies the parent's result and replaces
    `metadata["conclusion"]` with the rationale text (when present). The
    rationale is what flows into `self.history` for folded-off steps, so this
    keeps the human-readable summary in the prose-history layer.
"""
from __future__ import annotations

import re
from typing import Any, Dict, Optional

from agents.agents.qwen35_dsl import Qwen35DSLAgent


# Match a leading `Action: ...` line (or `**Action:**`, mixed casing) anywhere
# in the response body; we take the LAST such line above the `>>` line.
# `\**` slots before AND after `Action:` allow `Action:`, `**Action:**`, and
# `Action: **text**` to all be stripped to bare rationale text.
_ACTION_LINE_RE = re.compile(
    r"^[ \t]*\**\s*action\s*:\s*\**\s*(.*?)\s*\**\s*$",
    re.IGNORECASE | re.MULTILINE,
)


class Qwen35DSLActionAgent(Qwen35DSLAgent):
    """DSL agent that emits an `Action:` rationale line before the `>>` line."""

    # ---------------------------------------------------------------- prompt

    def _system_prompt(self, processed_width: int, processed_height: int) -> str:
        if self.coordinate_type == "absolute":
            res_line = (
                f"Coordinates X,Y are integer pixels with 0 <= X < {processed_width} "
                f"and 0 <= Y < {processed_height}."
            )
        else:
            res_line = (
                "Coordinates X,Y are integers in 0..999. The visible screen maps to "
                "a 1000x1000 normalized grid; (0,0) is the top-left."
            )

        return (
            "You drive a desktop computer. Every turn, emit at most two lines:\n\n"
            "  1. (optional) `Action: <one short imperative describing the UI step>`\n"
            "  2. (required) `>> <one or more CUA-DSL commands, separated by `;`>`\n\n"
            "No <think> block, no preamble, no trailing prose, no XML.\n\n"
            f"{res_line}\n\n"
            "# Verbs\n\n"
            "  click  X,Y [+MOD]      left-click; optional held modifier chord, e.g. +ctrl+shift\n"
            "  rclick X,Y [+MOD]      right-click\n"
            "  mclick X,Y [+MOD]      middle-click\n"
            "  dclick X,Y [+MOD]      double-click\n"
            "  tclick X,Y [+MOD]      triple-click\n"
            "  move   X,Y             move cursor only\n"
            "  drag   X1,Y1 X2,Y2     click and drag from (X1,Y1) to (X2,Y2)\n"
            "  scroll  N [@X,Y] [+MOD]  vertical scroll; signed N, positive = down; optional anchor; optional modifier\n"
            "  hscroll N [@X,Y] [+MOD]  horizontal scroll (positive = right)\n"
            "  key    K[+K]*          chord press, e.g. `key ctrl+a`\n"
            "  type   \"STR\"           type a literal string; escapes: \\\" \\\\ \\n \\t\n"
            "  wait   T               wait T seconds\n"
            "  done   ok              finish the task successfully\n"
            "  done   fail            finish the task as failed\n"
            "  say    \"STR\"           answer with a string and finish\n\n"
            "# Examples\n\n"
            "  Action: Click the File menu.\n"
            "  >> click 523,412\n\n"
            "  Action: Open a new tab.\n"
            "  >> click 100,200 +ctrl\n\n"
            "  Action: Drag the slider to the right.\n"
            "  >> drag 100,200 800,400\n\n"
            "  Action: Done.\n"
            "  >> done ok\n"
        )

    # --------------------------------------------------------------- parsing

    def _parse_response(
        self,
        response: str,
        *,
        original_width: Optional[int],
        original_height: Optional[int],
        processed_width: Optional[int],
        processed_height: Optional[int],
    ) -> Dict[str, Any]:
        parsed = super()._parse_response(
            response,
            original_width=original_width,
            original_height=original_height,
            processed_width=processed_width,
            processed_height=processed_height,
        )
        rationale = self._extract_rationale(response)
        if rationale:
            parsed.setdefault("metadata", {})["action_line"] = rationale
            # Only overwrite conclusion when the parent left the DSL line there
            # (no action_line yet) — preserves placeholder/error conclusions.
            if not parsed["metadata"].get("parse_error"):
                parsed["metadata"]["conclusion"] = rationale
        return parsed

    @staticmethod
    def _extract_rationale(response: str) -> Optional[str]:
        if not response:
            return None
        body = response.split("</think>", 1)[1] if "</think>" in response else response
        # Take the LAST Action: line above the FIRST `>>` line so that prompt
        # examples or stray earlier "Action:" tokens don't outvote the model's
        # actual rationale.
        dsl_start = body.find("\n>>") if not body.lstrip().startswith(">>") else 0
        if dsl_start < 0:
            search_region = body
        else:
            search_region = body[:dsl_start]
        matches = list(_ACTION_LINE_RE.finditer(search_region))
        if not matches:
            return None
        text = matches[-1].group(1).strip()
        return text or None


qwen35DSLActionAgent = Qwen35DSLActionAgent

__all__ = ["Qwen35DSLActionAgent", "qwen35DSLActionAgent"]
