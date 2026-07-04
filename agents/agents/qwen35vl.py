import json
import re
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple

from agents.agents.qwen3vl import Qwen3VLAgent
from agents.shared.llm_clients import call_llm, parse_qwen3vl_response


class Qwen35VLAgent(Qwen3VLAgent):
    """
    Qwen3.5-VL agent.

    Inherits Qwen3VLAgent and overrides only the three pieces that actually
    differ from Qwen3-VL in the upstream OSWorld implementation:

      1. Tool-call output format: bare XML <function=...><parameter=...>...</parameter>
         </function> blocks (vs Qwen3-VL's JSON-in-XML).
      2. Action set: adds `triple_click`, `hscroll`, `answer`; click and scroll
         actions accept an optional `text` parameter naming modifier keys.
      3. System prompt: the longer prompt with an <IMPORTANT> block, the
         current date, and a multi-line parameter example.

    Everything else (image processing, history window, OpenAI-compat call,
    message dumping, finish/save layout) is inherited unchanged.
    """

    _TOOL_CALL_RE = re.compile(r"<tool_call>(.*?)</tool_call>", re.DOTALL)
    _FUNCTION_RE = re.compile(r"<function=([^>]+)>")
    _PARAMETER_RE = re.compile(r"<parameter=([^>]+)>\s*(.*?)\s*</parameter>", re.DOTALL)

    _CLICK_ACTIONS = {
        "left_click",
        "right_click",
        "middle_click",
        "double_click",
        "triple_click",
    }
    _SCROLL_ACTIONS = {"scroll", "hscroll"}

    # ---- (3) System prompt -----------------------------------------------------

    def get_system_prompt(self) -> str:
        width, height = self.display_resolution
        tools_def = self._tools_def(width, height)
        return (
            "You are a multi-purpose intelligent assistant. Based on my requests, "
            "you can use tools to help me complete various tasks.\n\n"
            "# Tools\n\n"
            "You have access to the following functions:\n\n"
            "<tools>\n"
            + json.dumps(tools_def)
            + "\n</tools>\n\n"
            "If you choose to call a function ONLY reply in the following format with NO suffix:\n\n"
            "<tool_call>\n"
            "<function=example_function_name>\n"
            "<parameter=example_parameter_1>\n"
            "value_1\n"
            "</parameter>\n"
            "<parameter=example_parameter_2>\n"
            "This is the value for the second parameter\n"
            "that can span\n"
            "multiple lines\n"
            "</parameter>\n"
            "</function>\n"
            "</tool_call>\n\n"
            "<IMPORTANT>\n"
            "Reminder:\n"
            "- Function calls MUST follow the specified format: an inner <function=...></function> "
            "block must be nested within <tool_call></tool_call> XML tags\n"
            "- Required parameters MUST be specified\n"
            "- You may provide optional reasoning for your function call in natural language BEFORE "
            "the function call, but NOT after\n"
            "- If there is no function call available, answer the question like normal with your "
            "current knowledge and do not tell the user about function calls\n"
            f"- The current date is {datetime.today().strftime('%A, %B %d, %Y')}.\n"
            "</IMPORTANT>\n\n"
            "# Response format\n\n"
            "Response format for every step:\n"
            "1) Action: a short imperative describing what to do in the UI.\n"
            "2) A single <tool_call>...</tool_call> block.\n\n"
            "Rules:\n"
            "- Output exactly in the order: Action, <tool_call>.\n"
            "- Be brief: one sentence for Action.\n"
            "- Do not output anything else outside those parts.\n"
            "- If finishing, use action=terminate in the tool call."
        )

    # ---- (2) Action set --------------------------------------------------------

    @staticmethod
    def _tools_def(width: int, height: int) -> Dict[str, Any]:
        description = (
            "Use a mouse and keyboard to interact with a computer, and take screenshots.\n"
            "* This is an interface to a desktop GUI. You do not have access to a terminal or "
            "applications menu. You must click on desktop icons to start applications.\n"
            "* Some applications may take time to start or process actions, so you may need to "
            "wait and take successive screenshots to see the results of your actions.\n"
            f"* The screen's resolution is {width}x{height}.\n"
            "* Whenever you intend to move the cursor to click on an element like an icon, you "
            "should consult a screenshot to determine the coordinates of the element before "
            "moving the cursor.\n"
            "* If you tried clicking on a program or link but it failed to load, even after "
            "waiting, try adjusting your cursor position so that the tip of the cursor visually "
            "falls on the element that you want to click.\n"
            "* Make sure to click any buttons, links, icons, etc with the cursor tip in the "
            "center of the element. Don't click boxes on their edges unless asked."
        )
        action_description = (
            "\n"
            "* `key`: Performs key down presses on the arguments passed in order, then performs "
            "key releases in reverse order.\n"
            "* `type`: Type a string of text on the keyboard.\n"
            "* `mouse_move`: Move the cursor to a specified (x, y) pixel coordinate on the screen.\n"
            "* `left_click`: Click the left mouse button at a specified (x, y) pixel coordinate. "
            "Optional `text` parameter can specify modifier keys (e.g., \"ctrl\", \"shift\", "
            "\"ctrl+shift\") that will be held during the click.\n"
            "* `left_click_drag`: Click and drag the cursor to a specified (x, y) coordinate.\n"
            "* `right_click`: Click the right mouse button at a specified (x, y) pixel coordinate. "
            "Optional `text` parameter can specify modifier keys.\n"
            "* `middle_click`: Click the middle mouse button at a specified (x, y) pixel coordinate. "
            "Optional `text` parameter can specify modifier keys.\n"
            "* `double_click`: Double-click the left mouse button at a specified (x, y) pixel "
            "coordinate. Optional `text` parameter can specify modifier keys.\n"
            "* `triple_click`: Triple-click the left mouse button at a specified (x, y) pixel "
            "coordinate. Optional `text` parameter can specify modifier keys.\n"
            "* `scroll`: Performs a scroll of the mouse scroll wheel. Optional `text` parameter "
            "can specify a modifier key (e.g., \"shift\", \"ctrl\") to hold during scrolling.\n"
            "* `hscroll`: Performs a horizontal scroll (mapped to regular scroll). Optional `text` "
            "parameter can specify a modifier key to hold during scrolling.\n"
            "* `wait`: Wait specified seconds for the change to happen.\n"
            "* `terminate`: Terminate the current task and report its completion status.\n"
            "* `answer`: Answer a question."
        )
        return {
            "type": "function",
            "function": {
                "name": "computer_use",
                "description": description,
                "parameters": {
                    "type": "object",
                    "required": ["action"],
                    "properties": {
                        "action": {
                            "type": "string",
                            "description": action_description,
                            "enum": [
                                "key",
                                "type",
                                "mouse_move",
                                "left_click",
                                "left_click_drag",
                                "right_click",
                                "middle_click",
                                "double_click",
                                "triple_click",
                                "scroll",
                                "hscroll",
                                "wait",
                                "terminate",
                                "answer",
                            ],
                        },
                        "keys": {"type": "array", "description": "Required only by `action=key`."},
                        "text": {
                            "type": "string",
                            "description": (
                                "Required by `action=type` and `action=answer`. Optional for "
                                "click actions to specify modifier keys (e.g., 'ctrl', 'shift', "
                                "'ctrl+shift'). Optional for scroll/hscroll to specify a modifier "
                                "key to hold during scrolling."
                            ),
                        },
                        "coordinate": {"type": "array", "description": "(x, y) coordinates."},
                        "coordinate2": {
                            "type": "array",
                            "description": "(x2, y2) coordinates for drag end position.",
                        },
                        "pixels": {"type": "number", "description": "Scroll amount."},
                        "time": {"type": "number", "description": "Seconds to wait."},
                        "status": {
                            "type": "string",
                            "description": "Task status for terminate.",
                            "enum": ["success", "failure"],
                        },
                    },
                },
            },
        }

    # ---- (1) Step + XML response parsing --------------------------------------

    def step(self, obs, action_outputs):
        # Identical orchestration to Qwen3VLAgent.step — only the parser swaps.
        self.step_idx += 1

        processed_image_b64, processed_path = self.process_image(obs['screen']['path'])
        self.screenshots.append(processed_image_b64)
        self.b64_to_path[processed_image_b64] = processed_path

        messages = self.build_messages(processed_image_b64)
        self.save_messages(messages)

        print(f"Calling LLM with temperature: {self.temperature}")
        response = call_llm(
            messages,
            self.model,
            self.temperature,
            self.top_p,
            self.top_k,
        )

        self.responses.append(response)

        parsed_response = self._parse_response(response)

        self.all_model_responses.append(response)
        self.all_parsed_responses.append(parsed_response)

        actions = parsed_response['actions']
        metadata = parsed_response['metadata']

        self.history.append(metadata['conclusion'])

        if self.verbose:
            print(f"Step {self.step_idx + 1}:")
            print(f"  Conclusion: {metadata['conclusion']}")
            print(f"  Action Type: {metadata['action_type']}")
            print(f"  Actions: {actions}")

        tool_id = f'qwen35vl_step_{self.step_idx}'

        if metadata['is_terminal']:
            self.done = True
            return [{'tool_id': tool_id, 'actions': actions, 'metadata': metadata}]

        if metadata['wait_time'] is not None:
            return [{
                'tool_id': tool_id,
                'actions': [{'action': 'wait', 'time': metadata['wait_time']}],
                'metadata': metadata,
            }]

        return [{'tool_id': tool_id, 'actions': actions, 'metadata': metadata}]

    def _parse_response(self, response: str) -> Dict[str, Any]:
        """
        Parse a Qwen3.5-VL response and return the same shape as
        parse_qwen3vl_response. We extract the XML tool call into an
        ``action_json`` dict, remap Qwen3.5-only verbs (`hscroll`, `answer`)
        onto verbs the upstream parser already handles, then reuse it for
        action dispatch.
        """
        if not response or not isinstance(response, str):
            return _empty_screenshot_action("Empty or invalid response")

        action_json, conclusion = self._extract_action_json(response)
        if action_json is None:
            return _empty_screenshot_action(
                conclusion or "Failed to parse Qwen3.5-VL XML tool call",
                parse_error=True,
            )

        modifier_text = action_json.pop("__modifier_text", None)
        answer_text = action_json.pop("__answer_text", None)

        synthetic = self._format_as_qwen3vl_jsonxml(action_json, conclusion)
        parsed = parse_qwen3vl_response(synthetic)

        if modifier_text:
            # The runner action API has no held-modifier primitive, so the
            # closest we can get is press the chord immediately before the
            # click/scroll. Logged for visibility; intent is preserved even
            # though hold-during-click isn't.
            parsed = self._apply_modifier_keys(parsed, modifier_text)

        if answer_text is not None:
            parsed.setdefault("metadata", {})["answer"] = answer_text

        return parsed

    def _extract_action_json(
        self, response: str
    ) -> Tuple[Optional[Dict[str, Any]], Optional[str]]:
        body = response
        if "</think>" in body:
            body = body.split("</think>", 1)[1]

        conclusion: Optional[str] = None
        for line in body.split("\n"):
            stripped = line.strip()
            if stripped.lower().startswith("action:"):
                conclusion = stripped.split("Action:", 1)[-1].strip()
                break

        match = self._TOOL_CALL_RE.search(body)
        if not match:
            return None, conclusion

        inner = match.group(1)
        func_match = self._FUNCTION_RE.search(inner)
        if not func_match or func_match.group(1).strip() != "computer_use":
            return None, conclusion

        params: Dict[str, Any] = {}
        for pmatch in self._PARAMETER_RE.finditer(inner):
            name = pmatch.group(1).strip()
            params[name] = self._coerce_value(pmatch.group(2))

        if "action" not in params:
            return None, conclusion

        params = self._normalize_action_json(params)
        return params, conclusion

    @staticmethod
    def _coerce_value(raw: str) -> Any:
        text = raw.strip()
        if text.startswith("[") or text.startswith("{"):
            try:
                return json.loads(text)
            except json.JSONDecodeError:
                pass
        return text

    @classmethod
    def _normalize_action_json(cls, action_json: Dict[str, Any]) -> Dict[str, Any]:
        result = dict(action_json)
        action = result.get("action")

        # Pull modifier-text aside: parse_qwen3vl_response treats `text` as the
        # typed string for action=type, so leaving it on a click would corrupt
        # dispatch. We re-inject it as a chord-press in _apply_modifier_keys.
        if action in cls._CLICK_ACTIONS or action in cls._SCROLL_ACTIONS:
            text = result.get("text")
            if text:
                result["__modifier_text"] = text
            result.pop("text", None)

        # hscroll has no upstream verb; the OSWorld 3.5 agent also maps it to
        # plain scroll, so do the same.
        if action == "hscroll":
            result["action"] = "scroll"

        # answer is a terminate-with-payload variant. Stash the text in
        # metadata and dispatch as terminate so the loop stops cleanly.
        if action == "answer":
            result["__answer_text"] = result.get("text", "")
            result["action"] = "terminate"
            result.setdefault("status", "success")
            result.pop("text", None)

        # XML-encoded values arrive as strings; coerce the ones the upstream
        # dispatcher expects to be lists/numbers.
        for key in ("coordinate", "coordinate2"):
            value = result.get(key)
            if isinstance(value, str):
                try:
                    result[key] = json.loads(value)
                except json.JSONDecodeError:
                    result.pop(key, None)
        for key in ("pixels", "time"):
            value = result.get(key)
            if isinstance(value, str):
                try:
                    result[key] = float(value)
                except ValueError:
                    result.pop(key, None)
        keys_value = result.get("keys")
        if isinstance(keys_value, str):
            try:
                parsed_keys = json.loads(keys_value)
                result["keys"] = parsed_keys if isinstance(parsed_keys, list) else [keys_value]
            except json.JSONDecodeError:
                result["keys"] = [keys_value]

        return result

    @staticmethod
    def _format_as_qwen3vl_jsonxml(
        action_json: Dict[str, Any],
        conclusion: Optional[str],
    ) -> str:
        clean = {k: v for k, v in action_json.items() if not k.startswith("__")}
        payload = {"name": "computer_use", "arguments": clean}
        head = f"Action: {conclusion}\n" if conclusion else ""
        return head + "<tool_call>\n" + json.dumps(payload) + "\n</tool_call>"

    @staticmethod
    def _apply_modifier_keys(parsed: Dict[str, Any], modifier_text: str) -> Dict[str, Any]:
        keys = [k.strip().lower() for k in str(modifier_text).split("+") if k.strip()]
        if not keys:
            return parsed
        result = dict(parsed)
        prefix: List[Dict[str, Any]] = [{"keyboard": {"keys": keys}}]
        result["actions"] = prefix + list(result.get("actions", []))
        result.setdefault("metadata", {})["modifier_keys"] = keys
        return result


def _empty_screenshot_action(conclusion: str, *, parse_error: bool = False) -> Dict[str, Any]:
    metadata: Dict[str, Any] = {
        "thought": "",
        "conclusion": conclusion,
        "action_type": "screenshot",
        "is_terminal": False,
        "wait_time": None,
    }
    if parse_error:
        metadata["parse_error"] = True
    return {
        "actions": [{"action": "screenshot"}],
        "metadata": metadata,
    }
