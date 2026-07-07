"""
Qwen3.5-VL agent that speaks CUA-DSL (v1) instead of the XML <tool_call> grammar.

Subclasses Qwen35RealAgent. Overrides three things:

  1. `_system_prompt`: replaces the JSON tool definition + XML envelope with a
     single-line DSL where every step is one `>> ...` line.
  2. `_parse_response`: walks the `>>` line, splits commands on `;`, converts
     each command to the same `action_json` shape that the parent's
     `_actions_from_json` already understands.
  3. Defaults: `history_n=200` (DSL output is ~10 tokens/step so even long
     rollouts fit in context) and no rationale prose around the action line.

Grammar:
  line  := ">>" cmd (";" cmd)*
  cmd   := verb arg*
  verbs:
    click  X,Y [+MOD]            left-click; +MOD is a held chord, e.g. +ctrl+shift
    rclick X,Y [+MOD]            right-click
    mclick X,Y [+MOD]            middle-click
    dclick X,Y [+MOD]            double-click
    tclick X,Y [+MOD]            triple-click
    move   X,Y                   move cursor only
    drag   X1,Y1 X2,Y2           click-drag from (X1,Y1) to (X2,Y2)
    scroll  N [@X,Y] [+MOD]      vertical scroll; signed N (positive = down)
    hscroll N [@X,Y] [+MOD]      horizontal scroll (positive = right)
    key    K[+K]*                chord press, e.g. `key ctrl+a`
    type   "STR"                 escapes: \\" \\\\ \\n \\t
    wait   T                     sleep T seconds
    done   ok | done fail        terminate the task
    say    "STR"                 answer with a string and finish
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional, Tuple

from agents.agents.qwen35_real import Qwen35RealAgent


_VERB_TO_ACTION = {
    "click":   "left_click",
    "rclick":  "right_click",
    "mclick":  "middle_click",
    "dclick":  "double_click",
    "tclick":  "triple_click",
    "move":    "mouse_move",
    "drag":    "left_click_drag",
    "scroll":  "scroll",
    "hscroll": "hscroll",
    "key":     "key",
    "type":    "type",
    "wait":    "wait",
    "done":    "terminate",
    "say":     "answer",
}

_POINT_VERBS = {"click", "rclick", "mclick", "dclick", "tclick", "move"}
_SCROLL_VERBS = {"scroll", "hscroll"}


class _DSLParseError(ValueError):
    pass


class Qwen35DSLAgent(Qwen35RealAgent):
    """Qwen3.5-VL agent using the compressed CUA-DSL v1 grammar."""

    _DSL_LINE_RE = re.compile(r"^[ \t]*>>[ \t]*(.*?)[ \t]*$", re.MULTILINE)
    _COORD_RE = re.compile(r"^\s*(-?\d+)\s*,\s*(-?\d+)\s*$")

    def __init__(self, *args, **kwargs):
        agent_args = kwargs.setdefault("agent_args", {})
        agent_args.setdefault("history_n", 200)
        agent_args.setdefault("disable_thinking", True)
        agent_args.setdefault("incremental_messages", True)
        super().__init__(*args, **kwargs)

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
            "You drive a desktop computer. Every turn, emit exactly one action line "
            "in the CUA-DSL grammar below. Output nothing else: no rationale, no "
            "<think>, no XML, no preamble, no trailing prose.\n\n"
            "# Output format\n\n"
            "  >> CMD (; CMD)*\n\n"
            "Start the line with `>>`. Multiple commands on one line are separated "
            "by `;`. Use a single command per line unless they form one atomic UI "
            "step (e.g. click then type).\n\n"
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
            "  >> click 523,412\n"
            "  >> click 100,200 +ctrl\n"
            "  >> drag 100,200 800,400\n"
            "  >> scroll -3 @512,400\n"
            "  >> click 220,330; type \"hello\"; key enter\n"
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
        if not response or not isinstance(response, str) or not response.strip():
            return self._empty_screenshot_action("Empty or invalid response")

        body = response
        if "</think>" in body:
            body = body.split("</think>", 1)[1]

        match = self._DSL_LINE_RE.search(body)
        if not match:
            return self._empty_screenshot_action(
                "No `>>` line in response", parse_error=True
            )

        line = match.group(1).strip()
        commands = _split_commands(line)
        if not commands:
            return self._empty_screenshot_action("Empty `>>` line", parse_error=True)

        actions: List[Dict[str, Any]] = []
        metadata: Dict[str, Any] = {
            "thought": "",
            "conclusion": line,
            "action_type": None,
            "is_terminal": False,
            "wait_time": None,
            "dsl": line,
        }
        last_action_type: Optional[str] = None

        for cmd in commands:
            try:
                action_jsons = self._command_to_action_jsons(cmd)
            except _DSLParseError as exc:
                return self._empty_screenshot_action(
                    f"Bad command `{cmd}`: {exc}", parse_error=True
                )
            for action_json in action_jsons:
                last_action_type = action_json.get("action") or last_action_type
                sub_actions, sub_metadata = self._actions_from_json(
                    action_json,
                    original_width=original_width,
                    original_height=original_height,
                    processed_width=processed_width,
                    processed_height=processed_height,
                )
                actions.extend(sub_actions)
                if sub_metadata.get("is_terminal") and not metadata["is_terminal"]:
                    metadata["is_terminal"] = True
                    metadata["status"] = sub_metadata.get("status", "success")
                    if "answer" in sub_metadata:
                        metadata["answer"] = sub_metadata["answer"]
                if (
                    sub_metadata.get("wait_time") is not None
                    and metadata["wait_time"] is None
                ):
                    metadata["wait_time"] = sub_metadata["wait_time"]

        metadata["action_type"] = last_action_type or "screenshot"

        if (
            not actions
            and not metadata["is_terminal"]
            and metadata["wait_time"] is None
        ):
            return self._empty_screenshot_action(
                "No executable command parsed", parse_error=True
            )
        return {"actions": actions, "metadata": metadata}

    # ----------------------------------------------------- command → action_json

    def _command_to_action_jsons(self, cmd: str) -> List[Dict[str, Any]]:
        tokens, modifier = _strip_modifier(cmd)
        if not tokens:
            raise _DSLParseError("empty command")

        verb = tokens[0].lower()
        args = tokens[1:]
        if verb not in _VERB_TO_ACTION:
            raise _DSLParseError(f"unknown verb {verb!r}")
        action_name = _VERB_TO_ACTION[verb]

        if verb in _POINT_VERBS:
            if len(args) != 1:
                raise _DSLParseError(f"{verb} expects X,Y; got {args}")
            x, y = _parse_point(args[0])
            action_json: Dict[str, Any] = {"action": action_name, "coordinate": [x, y]}
            if modifier:
                action_json["text"] = "+".join(modifier)
            return [action_json]

        if verb == "drag":
            if len(args) != 2:
                raise _DSLParseError(f"drag expects X1,Y1 X2,Y2; got {args}")
            x1, y1 = _parse_point(args[0])
            x2, y2 = _parse_point(args[1])
            # The parent's left_click_drag carries only the end point and
            # assumes the cursor is already at the start. Prepend an explicit
            # move so the start point is honored regardless of cursor state.
            return [
                {"action": "mouse_move", "coordinate": [x1, y1]},
                {"action": "left_click_drag", "coordinate": [x2, y2]},
            ]

        if verb in _SCROLL_VERBS:
            if not args:
                raise _DSLParseError(f"{verb} expects N")
            pixels = _parse_int(args[0])
            action_json = {"action": action_name, "pixels": pixels}
            for extra in args[1:]:
                if extra.startswith("@"):
                    x, y = _parse_point(extra[1:])
                    action_json["coordinate"] = [x, y]
                else:
                    raise _DSLParseError(f"unexpected scroll arg {extra!r}")
            if modifier:
                action_json["text"] = "+".join(modifier)
            return [action_json]

        if verb == "key":
            chord = modifier or _parse_chord(args)
            if not chord:
                raise _DSLParseError("key expects K[+K]*")
            return [{"action": "key", "keys": chord}]

        if verb == "type":
            if len(args) != 1 or not _is_quoted(args[0]):
                raise _DSLParseError("type expects a quoted string")
            return [{"action": "type", "text": _unquote(args[0])}]

        if verb == "wait":
            if len(args) != 1:
                raise _DSLParseError("wait expects T")
            return [{"action": "wait", "time": _parse_float(args[0])}]

        if verb == "done":
            if len(args) != 1 or args[0] not in {"ok", "fail"}:
                raise _DSLParseError("done expects `ok` or `fail`")
            status = "success" if args[0] == "ok" else "failure"
            return [{"action": "terminate", "status": status}]

        if verb == "say":
            if len(args) != 1 or not _is_quoted(args[0]):
                raise _DSLParseError("say expects a quoted string")
            return [{"action": "answer", "text": _unquote(args[0])}]

        raise _DSLParseError(f"unhandled verb {verb!r}")


# --------------------------------------------------------------- helpers


def _split_commands(line: str) -> List[str]:
    """Split a DSL line on `;` while keeping `"..."` strings intact."""
    out: List[str] = []
    buf: List[str] = []
    in_str = False
    escape = False
    for ch in line:
        if in_str:
            buf.append(ch)
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_str = False
        elif ch == '"':
            in_str = True
            buf.append(ch)
        elif ch == ";":
            token = "".join(buf).strip()
            if token:
                out.append(token)
            buf = []
        else:
            buf.append(ch)
    tail = "".join(buf).strip()
    if tail:
        out.append(tail)
    return out


def _tokenize(cmd: str) -> List[str]:
    """Whitespace-tokenize a command, treating `"..."` (with escapes) as one token."""
    out: List[str] = []
    buf: List[str] = []
    in_str = False
    escape = False
    for ch in cmd:
        if in_str:
            buf.append(ch)
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_str = False
                out.append("".join(buf))
                buf = []
        elif ch == '"':
            if buf:
                out.append("".join(buf))
                buf = []
            in_str = True
            buf.append(ch)
        elif ch.isspace():
            if buf:
                out.append("".join(buf))
                buf = []
        else:
            buf.append(ch)
    if in_str or buf:
        out.append("".join(buf))
    return out


def _strip_modifier(cmd: str) -> Tuple[List[str], List[str]]:
    """Peel a trailing `+ctrl+shift` chord off the tokenized command."""
    tokens = _tokenize(cmd)
    modifier: List[str] = []
    while tokens and tokens[-1].startswith("+") and not _is_quoted(tokens[-1]):
        last = tokens.pop()
        modifier = [k for k in last.lstrip("+").split("+") if k] + modifier
    return tokens, modifier


def _parse_point(token: str) -> Tuple[int, int]:
    m = Qwen35DSLAgent._COORD_RE.match(token)
    if not m:
        raise _DSLParseError(f"bad point {token!r}")
    return int(m.group(1)), int(m.group(2))


def _parse_chord(tokens: List[str]) -> List[str]:
    keys: List[str] = []
    for token in tokens:
        for part in token.lstrip("+").split("+"):
            part = part.strip()
            if part:
                keys.append(part)
    return keys


def _parse_int(token: str) -> int:
    try:
        return int(token)
    except ValueError as exc:
        raise _DSLParseError(f"bad int {token!r}") from exc


def _parse_float(token: str) -> float:
    try:
        return float(token)
    except ValueError as exc:
        raise _DSLParseError(f"bad number {token!r}") from exc


def _is_quoted(token: str) -> bool:
    return len(token) >= 2 and token.startswith('"') and token.endswith('"')


def _unquote(token: str) -> str:
    body = token[1:-1]
    return body.encode("utf-8").decode("unicode_escape")


qwen35DSLAgent = Qwen35DSLAgent

__all__ = ["Qwen35DSLAgent", "qwen35DSLAgent"]
