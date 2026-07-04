"""Qwen3-VL / Kimi computer-use shared logic (system prompt + response parser).

Single source of truth for the prompt, tool protocol, and response parser
shared by the local agent loops (`agents/agents/qwen3vl.py`,
`agents/agents/kimi.py`) and the prime-rl/verifiers adapter. The protocol is
text-embedded tool calling: the tool schema rides in the system prompt inside
<tools></tools> tags and the model answers with one
<tool_call>{"name": ..., "arguments": ...}</tool_call> block per turn, with
coordinates on a 0-1000 grid scaled to the real resolution at parse time.

Rollout note: the local agent loops maintain a sliding window (last
`history_n` turns as messages, older turns as a one-line text summary). The
adapter keeps the full message history instead — assistant text turns are the
action record — and bounds context via screenshot pruning
(`keep_recent_screenshots`, default 2 ≈ the agents' history_n=1 window).
"""

from __future__ import annotations

import json
from typing import Any, Dict, List, Optional, Tuple



def convert_point_format_qwen3vl(x, y, scale_dims=True, scale_dims_ratio=(1920 / 1000, 1080 / 1000)):
    if scale_dims:
        x = x * scale_dims_ratio[0]
        y = y * scale_dims_ratio[1]
    return int(x), int(y)


def parse_qwen3vl_response(response, scale_dims=True, scale_dims_ratio=(1920 / 1000, 1080 / 1000)):
    if not response or not isinstance(response, str):
        return {
            "actions": [{"action": "screenshot"}],
            "metadata": {
                "thought": "Empty or invalid response",
                "conclusion": "Retrying with screenshot",
                "action_type": "screenshot",
                "is_terminal": False,
                "wait_time": None,
                "parse_error": True,
            },
        }

    thought = response.split("</think>")[0]
    conclusion = None
    if "</think>" in response:
        response = response.split("</think>")[1]

    printable_ratio = sum(1 for c in response if c.isprintable() or c.isspace()) / max(len(response), 1)
    if printable_ratio < 0.5:
        print(f"[parse_qwen3vl_response] Warning: Response appears garbled (printable ratio: {printable_ratio:.2f})")
        return {
            "actions": [{"action": "screenshot"}],
            "metadata": {
                "thought": "Garbled response detected",
                "conclusion": "Retrying with screenshot",
                "action_type": "screenshot",
                "is_terminal": False,
                "wait_time": None,
                "parse_error": True,
            },
        }

    if "<tool_call>" in response and "</tool_call>" in response:
        action = response.split("<tool_call>")[-1].split("</tool_call>")[0]
    else:
        try:
            action = '{"name": "computer_use"' + response.split('{"name": "computer_use"')[1].split("}}")[0] + "}}"
        except Exception as exc:
            print(f"[parse_qwen3vl_response] Error parsing action, switching to wait: {exc}", response)
            action = '{"action": "wait", "time": 1.0}'
            conclusion = "cannot parse action. waiting for 1 second and trying again"

    for line in response.split("\n"):
        if "Action:" in line:
            conclusion = line.split("Action:")[-1].strip()
    if conclusion is None:
        conclusion = response.split("<tool_call>")[0].strip()

    try:
        parsed_action = json.loads(action.strip("\n"))
        if "arguments" in parsed_action:
            action_json = parsed_action["arguments"]
        elif "action" in parsed_action:
            action_json = parsed_action
        else:
            raise ValueError("No 'arguments' or 'action' key in parsed JSON")
    except (json.JSONDecodeError, ValueError, KeyError) as exc:
        print(f"[parse_qwen3vl_response] Error parsing action JSON: {exc}", action)
        return {
            "actions": [{"action": "screenshot"}],
            "metadata": {
                "thought": thought,
                "conclusion": f"Parse error: {exc}",
                "action_type": "screenshot",
                "is_terminal": False,
                "wait_time": None,
                "parse_error": True,
            },
        }

    if "action" not in action_json:
        print(f"[parse_qwen3vl_response] Missing 'action' key in: {action_json}")
        return {
            "actions": [{"action": "screenshot"}],
            "metadata": {
                "thought": thought,
                "conclusion": "Missing action key",
                "action_type": "screenshot",
                "is_terminal": False,
                "wait_time": None,
                "parse_error": True,
            },
        }

    metadata = {
        "thought": thought,
        "conclusion": conclusion,
        "action_type": action_json["action"],
        "is_terminal": False,
        "wait_time": None,
    }

    if action_json["action"] == "key":
        actions = [{"keyboard": {"keys": action_json["keys"]}}]
    elif action_json["action"] == "type":
        actions = []
        if action_json.get("clear"):
            actions.append({"keyboard": {"keys": ["ctrl", "a"]}})
        actions.append({"keyboard": {"text": action_json["text"]}})
        if action_json.get("enter"):
            actions.append({"keyboard": {"keys": ["Return"]}})
    elif action_json["action"] == "mouse_move":
        x, y = convert_point_format_qwen3vl(
            action_json["coordinate"][0],
            action_json["coordinate"][1],
            scale_dims,
            scale_dims_ratio,
        )
        actions = [{"mouse": {"move": [x, y]}}]
    elif action_json["action"] in {"left_click", "click"}:
        x, y = convert_point_format_qwen3vl(
            action_json["coordinate"][0],
            action_json["coordinate"][1],
            scale_dims,
            scale_dims_ratio,
        )
        actions = [{"mouse": {"left_click": [x, y]}}]
    elif action_json["action"] == "right_click":
        x, y = convert_point_format_qwen3vl(
            action_json["coordinate"][0],
            action_json["coordinate"][1],
            scale_dims,
            scale_dims_ratio,
        )
        actions = [{"mouse": {"right_click": [x, y]}}]
    elif action_json["action"] == "double_click":
        x, y = convert_point_format_qwen3vl(
            action_json["coordinate"][0],
            action_json["coordinate"][1],
            scale_dims,
            scale_dims_ratio,
        )
        actions = [{"mouse": {"double_click": [x, y]}}]
    elif action_json["action"] == "triple_click":
        x, y = convert_point_format_qwen3vl(
            action_json["coordinate"][0],
            action_json["coordinate"][1],
            scale_dims,
            scale_dims_ratio,
        )
        actions = [{"mouse": {"triple_click": [x, y]}}]
    elif action_json["action"] in {"left_click_drag", "drag"}:
        x1, y1 = convert_point_format_qwen3vl(
            action_json["coordinate"][0],
            action_json["coordinate"][1],
            scale_dims,
            scale_dims_ratio,
        )
        try:
            x2, y2 = convert_point_format_qwen3vl(
                action_json["coordinate2"][0],
                action_json["coordinate2"][1],
                scale_dims,
                scale_dims_ratio,
            )
        except Exception as exc:
            print(f"[parse_qwen3vl_response] Error parsing coordinate2: {exc}")
            print("Action json: ", action_json)
            x2, y2 = x1, y1
        actions = [{"mouse": {"left_click_drag": [[x1, y1], [x2, y2]]}}]
    elif action_json["action"] == "scroll":
        if "coordinate" in action_json:
            x, y = convert_point_format_qwen3vl(
                action_json["coordinate"][0],
                action_json["coordinate"][1],
                scale_dims,
                scale_dims_ratio,
            )
            actions = [
                {"mouse": {"move": [x, y]}},
                {"mouse": {"scroll": action_json["pixels"] if "pixels" in action_json else action_json.get("scroll", 0)}},
            ]
        else:
            actions = [{"mouse": {"scroll": action_json["pixels"] if "pixels" in action_json else action_json.get("scroll", 0)}}]
    elif action_json["action"] == "wait":
        actions = []
        metadata["wait_time"] = action_json.get("time", 1.0)
    elif action_json["action"] == "terminate":
        actions = []
        metadata["is_terminal"] = True
        metadata["status"] = action_json.get("status", "success")
    else:
        actions = []

    return {"actions": actions, "metadata": metadata}


# ---------------------------------------------------------------------------
# Prompts
# ---------------------------------------------------------------------------

_COMPUTER_USE_DESCRIPTION = """Use a mouse and keyboard to interact with a computer, and take screenshots.
* This is an interface to a desktop GUI. You do not have access to a terminal or applications menu. You must click on desktop icons to start applications.
* Some applications may take time to start or process actions, so you may need to wait and take successive screenshots to see the results of your actions. E.g. if you click on Firefox and a window doesn't open, try wait and taking another screenshot.
* The screen is {resolution}. IMPORTANT: give every (x, y) coordinate as integers on a 0-1000 normalized grid, where [0,0] is the top-left corner and [1000,1000] is the bottom-right corner. Do NOT use raw pixel values.
* Whenever you intend to move the cursor to click on an element like an icon, you should consult a screenshot to determine the coordinates of the element before moving the cursor.
* If you tried clicking on a program or link but it failed to load even after waiting, try adjusting your cursor position so that the tip of the cursor visually falls on the element that you want to click.
* Make sure to click any buttons, links, icons, etc with the cursor tip in the center of the element. Don't click boxes on their edges unless asked."""


def qwen_tools_def(resolution: Tuple[int, int]) -> Dict[str, Any]:
    width, height = resolution
    return {
        "type": "function",
        "function": {
            "name": "computer_use",
            "description": _COMPUTER_USE_DESCRIPTION.format(resolution=f"{width}x{height}"),
            "parameters": {
                "properties": {
                    "action": {
                        "description": """The action to perform. The available actions are:
* `key`: Performs key down presses on the arguments passed in order, then performs key releases in reverse order.
* `type`: Type a string of text on the keyboard.
* `mouse_move`: Move the cursor to a specified (x, y) pixel coordinate on the screen.
* `click`: Click the left mouse button at a specified (x, y) pixel coordinate on the screen.
* `left_click`: Click the left mouse button at a specified (x, y) pixel coordinate on the screen.
* `drag`: Click and drag the cursor to a specified (x, y) pixel coordinate on the screen.
* `right_click`: Click the right mouse button at a specified (x, y) pixel coordinate on the screen.
* `middle_click`: Click the middle mouse button at a specified (x, y) pixel coordinate on the screen.
* `double_click`: Double-click the left mouse button at a specified (x, y) pixel coordinate on the screen.
* `scroll`: Performs a scroll of the mouse scroll wheel.
* `wait`: Wait specified seconds for the change to happen.
* `terminate`: Terminate the current task and report its completion status.""",
                        "enum": ["key", "type", "mouse_move", "click", "left_click", "drag",
                                 "right_click", "middle_click", "double_click", "scroll", "wait", "terminate"],
                        "type": "string"
                    },
                    "keys": {"description": "Required only by `action=key`.", "type": "array"},
                    "text": {"description": "Required only by `action=type`.", "type": "string"},
                    "coordinate": {"description": "The x,y coordinates for mouse actions.", "type": "array"},
                    "coordinate2": {"description": "The x2,y2 coordinates for drag end position. Required only by `action=drag`.", "type": "array"},
                    "pixels": {"description": "The amount of scrolling.", "type": "number"},
                    "time": {"description": "The seconds to wait.", "type": "number"},
                    "status": {
                        "description": "The status of the task.",
                        "type": "string",
                        "enum": ["success", "failure"]
                    }
                },
                "required": ["action"],
                "type": "object"
            }
        }
    }


def kimi_tools_def() -> Dict[str, Any]:
    """osworld-aligned variant: relative 1000x1000 coordinates, no click/drag aliases."""
    return {
        "type": "function",
        "function": {
            "name_for_human": "computer_use",
            "name": "computer_use",
            "description": _COMPUTER_USE_DESCRIPTION.format(resolution="1000x1000"),
            "parameters": {
                "properties": {
                    "action": {
                        "description": """The action to perform. The available actions are:
* `key`: Performs key down presses on the arguments passed in order, then performs key releases in reverse order.
* `type`: Type a string of text on the keyboard.
* `mouse_move`: Move the cursor to a specified (x, y) pixel coordinate on the screen.
* `left_click`: Click the left mouse button at a specified (x, y) pixel coordinate on the screen.
* `left_click_drag`: Click and drag the cursor to a specified (x, y) pixel coordinate on the screen.
* `right_click`: Click the right mouse button at a specified (x, y) pixel coordinate on the screen.
* `middle_click`: Click the middle mouse button at a specified (x, y) pixel coordinate on the screen.
* `double_click`: Double-click the left mouse button at a specified (x, y) pixel coordinate on the screen.
* `scroll`: Performs a scroll of the mouse scroll wheel.
* `wait`: Wait specified seconds for the change to happen.
* `terminate`: Terminate the current task and report its completion status.""",
                        "enum": ["key", "type", "mouse_move", "left_click", "left_click_drag",
                                 "right_click", "middle_click", "double_click", "scroll", "wait", "terminate"],
                        "type": "string"
                    },
                    "keys": {"description": "Required only by `action=key`.", "type": "array"},
                    "text": {"description": "Required only by `action=type`.", "type": "string"},
                    "coordinate": {"description": "The x,y coordinates for mouse actions.", "type": "array"},
                    "coordinate2": {"description": "The x2,y2 coordinates for drag end position. Required only by `action=left_click_drag`.", "type": "array"},
                    "pixels": {"description": "The amount of scrolling.", "type": "number"},
                    "time": {"description": "The seconds to wait.", "type": "number"},
                    "status": {
                        "description": "The status of the task.",
                        "type": "string",
                        "enum": ["success", "failure"]
                    }
                },
                "required": ["action"],
                "type": "object"
            }
        }
    }


def wrap_system_prompt(tools_def: Dict[str, Any]) -> str:
    return """# Tools

You may call one or more functions to assist with the user query.

You are provided with function signatures within <tools></tools> XML tags:
<tools>
""" + json.dumps(tools_def) + """
</tools>

For each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:
<tool_call>
{"name": <function-name>, "arguments": <args-json-object>}
</tool_call>

# Response format

Response format for every step:
1) Action: a short imperative describing what to do in the UI.
2) A single <tool_call>...</tool_call> block containing only the JSON: {"name": <function-name>, "arguments": <args-json-object>}.

Rules:
- Output exactly in the order: Action, <tool_call>.
- Be brief: one sentence for Action.
- Do not output anything else outside those parts.
- If finishing, use action=terminate in the tool call."""


def qwen_system_prompt(resolution: Tuple[int, int]) -> str:
    return wrap_system_prompt(qwen_tools_def(resolution))


def kimi_system_prompt() -> str:
    return wrap_system_prompt(kimi_tools_def())


INSTRUCTION_TEMPLATE = """Please generate the next move according to the UI screenshot, instruction and previous actions.

Instruction: {instruction}

Previous actions:
None"""


__all__ = [
    "INSTRUCTION_TEMPLATE",
    "convert_point_format_qwen3vl",
    "kimi_system_prompt",
    "kimi_tools_def",
    "parse_qwen3vl_response",
    "qwen_system_prompt",
    "qwen_tools_def",
    "wrap_system_prompt",
]
