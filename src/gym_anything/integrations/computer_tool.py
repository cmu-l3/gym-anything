"""Provider-agnostic `computer` tool: schema, prompts, and action translation.

Pure helpers with no third-party dependencies, shared by the training-stack
adapters in this package. The tool exposes mouse/keyboard control plus
screenshot observation and translates each call into gym-anything action
dicts (`{"mouse": ...}` / `{"keyboard": ...}`).
"""

from __future__ import annotations

import json
from typing import Any, Dict, List, Tuple

ACTIONS = [
    "left_click",
    "double_click",
    "right_click",
    "middle_click",
    "mouse_move",
    "left_click_drag",
    "scroll",
    "key",
    "type",
    "wait",
    "screenshot",
    "terminate",
]

# Sentinels used by parse_tool_calls for malformed model output.
WRONG_TOOL = "__wrong_tool__"
PARSE_ERROR = "__parse_error__"


def make_computer_tool(coordinate_mode: str) -> Dict[str, Any]:
    if coordinate_mode == "norm1000":
        coord_desc = (
            "[x, y] in a 0-1000 normalized coordinate space; [0,0] is the "
            "top-left corner and [1000,1000] the bottom-right corner of the screen."
        )
    else:
        coord_desc = "[x, y] in raw screen pixels; origin is the top-left corner."
    return {
        "name": "computer",
        "description": (
            "Control the computer with mouse and keyboard and observe the "
            "screen. After every action you receive a new screenshot.\n"
            "Actions: left_click / double_click / right_click / middle_click "
            "(need `coordinate`), mouse_move (needs `coordinate`), "
            "left_click_drag (needs `coordinate` start and `coordinate2` end), "
            "scroll (needs `pixels`; negative scrolls down, optionally "
            "`coordinate` to scroll at), key (needs `keys`, e.g. "
            "[\"ctrl\",\"s\"] or [\"Return\"]), type (needs `text`), wait "
            "(needs `time` seconds), screenshot (no args), terminate (ends "
            "the episode; set `status`)."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "action": {"type": "string", "enum": ACTIONS},
                "coordinate": {
                    "type": "array",
                    "items": {"type": "number"},
                    "description": coord_desc,
                },
                "coordinate2": {
                    "type": "array",
                    "items": {"type": "number"},
                    "description": "Drag end point; same convention as `coordinate`.",
                },
                "text": {"type": "string", "description": "Text for action=type."},
                "keys": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Keys pressed together for action=key.",
                },
                "pixels": {
                    "type": "number",
                    "description": "Scroll amount for action=scroll.",
                },
                "time": {
                    "type": "number",
                    "description": "Seconds to wait for action=wait.",
                },
                "status": {
                    "type": "string",
                    "enum": ["success", "failure"],
                    "description": "Task outcome for action=terminate.",
                },
            },
            "required": ["action"],
        },
    }


def system_prompt(resolution: Tuple[int, int], coordinate_mode: str) -> str:
    # Conventions ported from the proven reference agents
    # (agents/agents/gemini_computer_use.py SYSTEM_INSTRUCTION): the target
    # application is already open, and wandering off into browsers/terminals
    # is the dominant failure mode to forbid explicitly.
    w, h = resolution
    if coordinate_mode == "norm1000":
        coords = (
            "Coordinates use a 0-1000 normalized space on both axes "
            f"(the real screen is {w}x{h} pixels; you never need pixel values)."
        )
    else:
        coords = f"Coordinates are raw pixels on a {w}x{h} screen."
    return (
        "You are operating a real computer through the `computer` tool to "
        "complete the task described by the user. The application you need "
        "is ALREADY OPEN on screen. Do not open a web browser, navigate to "
        "URLs, use search, or switch to a terminal unless the task itself "
        "requires it — interact directly with what is on screen using "
        "clicks, typing, and keyboard shortcuts. The screen content is "
        "provided to you as screenshots; a fresh screenshot follows every "
        f"action. {coords} Look carefully at the latest screenshot before "
        "every action and click at the center of targets. Applications can "
        "be slow: if the screen has not caught up with your action, use "
        "wait and then screenshot. Work step by step inside the open "
        "application until the task is fully complete, then call the tool "
        "with action=terminate."
    )


# Key-name normalization -> env (X11 keysym-ish) names, ported from the
# reference agents' keymap so models can use common names like "enter".
KEYMAP = {
    "control": "ctrl", "ctrl": "ctrl", "alt": "alt", "option": "alt",
    "shift": "shift", "meta": "super", "cmd": "super", "command": "super",
    "super": "super", "win": "super", "enter": "Return", "return": "Return",
    "tab": "Tab", "escape": "Escape", "esc": "Escape", "backspace": "BackSpace",
    "delete": "Delete", "del": "Delete", "space": "space", "spacebar": "space",
    "up": "Up", "down": "Down", "left": "Left", "right": "Right",
    "home": "Home", "end": "End", "pageup": "Prior", "pagedown": "Next",
}


def normalize_keys(keys: List[str]) -> List[str]:
    return [KEYMAP.get(str(k).strip().lower(), str(k).strip()) for k in keys if str(k).strip()]


def to_pixels(coord: Any, resolution: Tuple[int, int], mode: str) -> Tuple[int, int]:
    x, y = float(coord[0]), float(coord[1])
    if mode == "norm1000":
        x = x * resolution[0] / 1000.0
        y = y * resolution[1] / 1000.0
    return int(round(x)), int(round(y))


def translate_action(
    args: Dict[str, Any], resolution: Tuple[int, int], mode: str
) -> Dict[str, Any]:
    """Translate one computer-tool call into gym actions + control metadata.

    Returns {"actions": [...], "terminal": bool, "wait": float|None, "error": str|None}
    """
    out: Dict[str, Any] = {"actions": [], "terminal": False, "wait": None, "error": None}
    action = args.get("action")
    try:
        if action in ("left_click", "double_click", "right_click", "middle_click", "mouse_move"):
            x, y = to_pixels(args["coordinate"], resolution, mode)
            key = "move" if action == "mouse_move" else action
            out["actions"] = [{"mouse": {key: [x, y]}}]
        elif action == "left_click_drag":
            x1, y1 = to_pixels(args["coordinate"], resolution, mode)
            x2, y2 = to_pixels(args.get("coordinate2", args["coordinate"]), resolution, mode)
            out["actions"] = [{"mouse": {"left_click_drag": [[x1, y1], [x2, y2]]}}]
        elif action == "scroll":
            amount = args.get("pixels", -400)
            acts = []
            if args.get("coordinate"):
                x, y = to_pixels(args["coordinate"], resolution, mode)
                acts.append({"mouse": {"move": [x, y]}})
            acts.append({"mouse": {"scroll": amount}})
            out["actions"] = acts
        elif action == "key":
            keys = args.get("keys") or []
            if isinstance(keys, str):
                keys = keys.replace("+", " ").split()
            out["actions"] = [{"keyboard": {"keys": normalize_keys(list(keys))}}]
        elif action == "type":
            out["actions"] = [{"keyboard": {"text": str(args.get("text", ""))}}]
        elif action == "wait":
            out["wait"] = float(args.get("time", 1.0))
        elif action == "screenshot":
            pass  # no-op; a screenshot always follows
        elif action == "terminate":
            out["terminal"] = True
        else:
            out["error"] = f"Unknown action: {action!r}"
    except (KeyError, IndexError, TypeError, ValueError) as e:
        out["error"] = f"Malformed arguments for {action!r}: {e}"
    return out


def parse_tool_calls(message: Any) -> List[Tuple[str, Dict[str, Any]]]:
    """Extract (tool_call_id, arguments) pairs for `computer` calls.

    Calls to other tools yield {"action": WRONG_TOOL}; unparseable arguments
    yield {"action": PARSE_ERROR}.
    """
    calls = []
    tool_calls = getattr(message, "tool_calls", None)
    if tool_calls is None and isinstance(message, dict):
        tool_calls = message.get("tool_calls")
    for i, tc in enumerate(tool_calls or []):
        fn = getattr(tc, "function", None) or (tc.get("function") if isinstance(tc, dict) else None)
        name = getattr(fn, "name", None) or (fn.get("name") if isinstance(fn, dict) else None)
        name = name or getattr(tc, "name", None) or (tc.get("name") if isinstance(tc, dict) else None)
        raw = getattr(fn, "arguments", None) or (fn.get("arguments") if isinstance(fn, dict) else None)
        raw = raw if raw is not None else (getattr(tc, "arguments", None) or (tc.get("arguments") if isinstance(tc, dict) else None))
        tc_id = getattr(tc, "id", None) or (tc.get("id") if isinstance(tc, dict) else None) or f"call_{i}"
        if name != "computer":
            calls.append((tc_id, {"action": WRONG_TOOL, "__name__": name}))
            continue
        if isinstance(raw, str):
            try:
                args = json.loads(raw)
            except json.JSONDecodeError:
                args = {"action": PARSE_ERROR}
        elif isinstance(raw, dict):
            args = raw
        else:
            args = {"action": PARSE_ERROR}
        calls.append((tc_id, args))
    return calls


def screenshot_message(b64: str) -> Dict[str, Any]:
    return {
        "role": "user",
        "content": [
            {"type": "text", "text": "Current screen:"},
            {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{b64}"}},
        ],
    }


def prune_screenshots(messages: List[Any], keep_recent: int) -> List[Any]:
    """Replace all but the last `keep_recent` screenshots with placeholders."""
    if keep_recent is None or keep_recent < 0:
        return messages
    image_positions = []
    for i, msg in enumerate(messages):
        content = msg.get("content") if isinstance(msg, dict) else getattr(msg, "content", None)
        if isinstance(content, list) and any(
            isinstance(p, dict) and p.get("type") == "image_url" for p in content
        ):
            image_positions.append(i)
    drop = set(image_positions[:-keep_recent]) if keep_recent else set(image_positions)
    if not drop:
        return messages
    pruned = []
    for i, msg in enumerate(messages):
        if i not in drop:
            pruned.append(msg)
            continue
        content = msg.get("content")
        new_content = [
            p if not (isinstance(p, dict) and p.get("type") == "image_url")
            else {"type": "text", "text": "[older screenshot removed]"}
            for p in content
        ]
        pruned.append({**msg, "content": new_content})
    return pruned
