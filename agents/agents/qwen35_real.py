from __future__ import annotations

import ast
import copy
import json
import os
import re
import time
import uuid
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple

from agents.agents.base import BaseAgent
from agents.agents.image_pipeline import ImagePipelineMixin
from agents.shared.llm_clients import call_llm


class Qwen35RealAgent(ImagePipelineMixin, BaseAgent):
    """
    Qwen3.5-VL agent ported from OSWorld PR #448.

    This keeps the Qwen3.5-specific behavior from the upstream agent:
    XML function-call format, long-history screenshot folding, 1000x1000
    relative-coordinate prompting by default, and answer/terminate semantics.
    It adapts only the integration layer to Gym Anything: observations come from
    obs["screen"], model calls use the shared local OpenAI-compatible client,
    and parsed actions are returned as Gym Anything action dictionaries.
    """

    COLLAPSED_SCREENSHOT_TEXT = "This screenshot has been collapsed."

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

    def __init__(self, *args, **kwargs):
        self.agent_args = kwargs.get("agent_args", {})
        self.model = self.agent_args.get("model", "qwen35-vl")
        self.decoding_params = self.agent_args.get("decoding_params", {})
        self.temperature = self.agent_args.get(
            "temperature", self.decoding_params.get("temperature", 0.0)
        )
        self.top_p = self.decoding_params.get("top_p", self.agent_args.get("top_p", 0.9))
        self.top_k = self.decoding_params.get("top_k", self.agent_args.get("top_k", 20))
        self.max_tokens = self.decoding_params.get(
            "max_tokens", self.agent_args.get("max_tokens", 32768)
        )
        self.history_n = int(self.agent_args.get("history_n", 100))
        self.coordinate_type = self.agent_args.get("coordinate_type", "relative")
        self.image_max = int(self.agent_args.get("image_max", 20))
        self.fold_size = int(self.agent_args.get("fold_size", 10))
        self.collapse_text = self.agent_args.get(
            "collapse_text", self.COLLAPSED_SCREENSHOT_TEXT
        )
        self.disable_thinking = self.agent_args.get("disable_thinking", True)
        self.session_id = self.agent_args.get("session_id") or os.environ.get(
            "GYM_ANYTHING_AGENT_SESSION_ID"
        )
        self.incremental_messages = self._coerce_bool(
            self.agent_args.get(
                "incremental_messages",
                os.environ.get("GYM_ANYTHING_AGENT_INCREMENTAL_MESSAGES", "0"),
            )
        )
        self.incremental_include_assistant = self._coerce_bool(
            self.agent_args.get(
                "incremental_include_assistant",
                os.environ.get("GYM_ANYTHING_AGENT_INCREMENTAL_INCLUDE_ASSISTANT", "1"),
            )
        )
        if self.incremental_messages and not self.session_id:
            self.session_id = f"ga-agent-{uuid.uuid4().hex}"

        if self.coordinate_type not in {"relative", "absolute"}:
            raise ValueError("coordinate_type must be 'relative' or 'absolute'")
        if self.image_max < 1:
            raise ValueError("image_max must be >= 1")
        if self.fold_size < 1:
            raise ValueError("fold_size must be >= 1")

        self.exp_name = self.agent_args.get("exp_name", "exp")
        self.setup_custom_logger()

        self.done = False
        self.step_idx = -1
        self.folded_prefix_k = 0

        self.history: List[str] = []
        self.screenshots: List[str] = []
        self.responses: List[str] = []
        self.all_model_responses: List[str] = []
        self.all_parsed_responses: List[Dict[str, Any]] = []
        self.b64_to_path: Dict[str, str] = {}

        self.debug = kwargs.get("debug", False)
        self.verbose = kwargs.get("verbose", False)
        self._init_image_pipeline()

    @staticmethod
    def _coerce_bool(value, default: bool = False) -> bool:
        if value is None:
            return default
        if isinstance(value, bool):
            return value
        if isinstance(value, (int, float)):
            return bool(value)
        if isinstance(value, str):
            normalized = value.strip().lower()
            if normalized in {"1", "true", "yes", "on"}:
                return True
            if normalized in {"0", "false", "no", "off"}:
                return False
        raise ValueError(f"expected boolean value, got {value!r}")

    def setup_custom_logger(self):
        task_name = self.agent_args.get("task_name", "task")
        self.save_folder_custom = f"all_runs/{self.exp_name}/{self.model}/{task_name}"
        for run_number in range(1000):
            candidate = f"{self.save_folder_custom}/run_{run_number}"
            if os.path.exists(candidate):
                continue
            self.save_folder_custom = candidate
            break
        os.makedirs(self.save_folder_custom, exist_ok=False)

    def init(self, task_description, display_resolution, save_path):
        self.task_description = task_description
        self.display_resolution = display_resolution
        self.save_path = save_path

    def save_messages(self, messages):
        messages_to_save = copy.deepcopy(messages)
        for msg in messages_to_save:
            if msg.get("role") != "user" or not isinstance(msg.get("content"), list):
                continue
            for content in msg["content"]:
                if content.get("type") != "image_url":
                    continue
                image_url = content.get("image_url")
                if image_url is None:
                    image_uuid = content.get("uuid")
                    if image_uuid in self.uuid_to_path:
                        content["image_url"] = {
                            "url": self.uuid_to_path[image_uuid],
                            "cached": True,
                        }
                    continue
                url = image_url.get("url", "") if isinstance(image_url, dict) else ""
                if "base64," in url:
                    b64 = url.split("base64,", 1)[1]
                    if b64 in self.b64_to_path:
                        content["image_url"]["url"] = self.b64_to_path[b64]

        path = f"{self.save_folder_custom}/messages_step_{self.step_idx}.json"
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(messages_to_save, handle, indent=2, ensure_ascii=False)

    def _update_folding_state(self, total_screenshots: int) -> None:
        while (total_screenshots - self.folded_prefix_k) > self.image_max:
            self.folded_prefix_k += self.fold_size
        if self.folded_prefix_k > total_screenshots:
            self.folded_prefix_k = total_screenshots

    def _should_collapse_step(self, step_num_1based: int) -> bool:
        return step_num_1based <= self.folded_prefix_k

    def _wrap_tool_response(self, parts: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        return (
            [{"type": "text", "text": "<tool_response>\n"}]
            + parts
            + [{"type": "text", "text": "\n</tool_response>"}]
        )

    def _screen_size(self, screen_obs) -> Tuple[int, int]:
        image = self._load_image(screen_obs)
        return image.size

    def _processed_size(self, image_b64: str) -> Tuple[int, int]:
        if getattr(self, "image_format", None) == "prime_rgb":
            return self.prime_rgb_width, self.prime_rgb_height

        from base64 import b64decode
        from io import BytesIO

        from PIL import Image

        with Image.open(BytesIO(b64decode(image_b64))) as image:
            return image.size

    def _tool_description(self, processed_width: int, processed_height: int) -> str:
        resolution_line = (
            f"* The screen's resolution is {processed_width}x{processed_height}."
            if self.coordinate_type == "absolute"
            else "* The screen's resolution is 1000x1000."
        )
        return "\n".join(
            [
                "Use a mouse and keyboard to interact with a computer, and take screenshots.",
                "* This is an interface to a desktop GUI. You do not have access to a terminal or applications menu. You must click on desktop icons to start applications.",
                "* Some applications may take time to start or process actions, so you may need to wait and take successive screenshots to see the results of your actions.",
                resolution_line,
                "* Whenever you intend to move the cursor to click on an element like an icon, you should consult a screenshot to determine the coordinates of the element before moving the cursor.",
                "* If you tried clicking on a program or link but it failed to load, even after waiting, try adjusting your cursor position so that the tip of the cursor visually falls on the element that you want to click.",
                "* Make sure to click any buttons, links, icons, etc with the cursor tip in the center of the element. Don't click boxes on their edges unless asked.",
            ]
        )

    @staticmethod
    def _action_description() -> str:
        return """
* `key`: Performs key down presses on the arguments passed in order, then performs key releases in reverse order.
* `type`: Type a string of text on the keyboard.
* `mouse_move`: Move the cursor to a specified (x, y) pixel coordinate on the screen.
* `left_click`: Click the left mouse button at a specified (x, y) pixel coordinate on the screen. Optional `text` parameter can specify modifier keys (e.g., "ctrl", "shift", "ctrl+shift") that will be held during the click.
* `left_click_drag`: Click and drag the cursor to a specified (x, y) coordinate.
* `right_click`: Click the right mouse button at a specified (x, y) pixel coordinate on the screen. Optional `text` parameter can specify modifier keys that will be held during the click.
* `middle_click`: Click the middle mouse button at a specified (x, y) pixel coordinate on the screen. Optional `text` parameter can specify modifier keys that will be held during the click.
* `double_click`: Double-click the left mouse button at a specified (x, y) pixel coordinate on the screen. Optional `text` parameter can specify modifier keys that will be held during the click.
* `triple_click`: Triple-click the left mouse button at a specified (x, y) pixel coordinate on the screen. Optional `text` parameter can specify modifier keys that will be held during the click.
* `scroll`: Performs a scroll of the mouse scroll wheel. Optional `text` parameter can specify a modifier key (e.g., "shift", "ctrl") that will be held during scrolling.
* `hscroll`: Performs a horizontal scroll (mapped to regular scroll). Optional `text` parameter can specify a modifier key that will be held during scrolling.
* `wait`: Wait specified seconds for the change to happen.
* `terminate`: Terminate the current task and report its completion status.
* `answer`: Answer a question."""

    def _tools_def(self, processed_width: int, processed_height: int) -> Dict[str, Any]:
        return {
            "type": "function",
            "function": {
                "name": "computer_use",
                "description": self._tool_description(processed_width, processed_height),
                "parameters": {
                    "type": "object",
                    "required": ["action"],
                    "properties": {
                        "action": {
                            "type": "string",
                            "description": self._action_description(),
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
                            "description": "Required by `action=type` and `action=answer`. Optional for click actions (left_click, right_click, middle_click, double_click, triple_click) to specify modifier keys (e.g., 'ctrl', 'shift', 'ctrl+shift'). Optional for scroll actions (scroll, hscroll) to specify a modifier key (e.g., 'shift', 'ctrl') to hold during scrolling.",
                        },
                        "coordinate": {"type": "array", "description": "(x, y) coordinates."},
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

    def _system_prompt(self, processed_width: int, processed_height: int) -> str:
        tools_def = self._tools_def(processed_width, processed_height)
        return (
            "You are a multi-purpose intelligent assistant. Based on my requests, you can use tools to help me complete various tasks.\n\n"
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
            "- Function calls MUST follow the specified format: an inner <function=...></function> block must be nested within <tool_call></tool_call> XML tags\n"
            "- Required parameters MUST be specified\n"
            "- You may provide optional reasoning for your function call in natural language BEFORE the function call, but NOT after\n"
            "- If there is no function call available, answer the question like normal with your current knowledge and do not tell the user about function calls\n"
            f"- The current date is {datetime.today().strftime('%A, %B %d, %Y')}.\n"
            f"- Collapsed screenshots appear as text: {self.collapse_text}\n"
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

    def build_messages(self, processed_width: int, processed_height: int) -> List[Dict[str, Any]]:
        total_steps = len(self.screenshots)
        self._update_folding_state(total_steps)
        start_step = max(1, total_steps - self.history_n)

        previous_actions = [
            f"Step {idx + 1}: {self.history[idx]}"
            for idx in range(0, min(start_step - 1, len(self.history)))
        ]
        previous_actions_str = "\n".join(previous_actions) if previous_actions else "None"

        instruction_prompt = (
            "\nPlease generate the next move according to the UI screenshot, instruction and previous actions.\n\n"
            f"Instruction: {self.task_description}\n\n"
            "Previous actions:\n"
            f"{previous_actions_str}"
        )

        messages: List[Dict[str, Any]] = [
            {
                "role": "system",
                "content": [
                    {
                        "type": "text",
                        "text": self._system_prompt(processed_width, processed_height),
                    }
                ],
            }
        ]

        for step_num in range(start_step, total_steps + 1):
            is_first_turn = step_num == start_step
            is_current_turn = step_num == total_steps
            screenshot_b64 = self.screenshots[step_num - 1]
            screenshot_uuid = (
                self.screenshot_uuids[step_num - 1]
                if step_num - 1 < len(self.screenshot_uuids)
                else None
            )

            if self._should_collapse_step(step_num):
                parts = [{"type": "text", "text": self.collapse_text}]
                if is_first_turn:
                    user_content = [{"type": "text", "text": instruction_prompt}]
                else:
                    user_content = self._wrap_tool_response(parts)
            else:
                image_part = self._image_content(
                    screenshot_b64,
                    include_bytes=is_current_turn,
                    image_uuid=screenshot_uuid,
                )
                if is_first_turn:
                    user_content = [
                        image_part,
                        {"type": "text", "text": instruction_prompt},
                    ]
                else:
                    user_content = self._wrap_tool_response([image_part])
            messages.append({"role": "user", "content": user_content})

            response_idx = step_num - 1
            if step_num <= total_steps - 1 and response_idx < len(self.responses):
                messages.append(
                    {
                        "role": "assistant",
                        "content": [
                            {"type": "text", "text": self.responses[response_idx]},
                        ],
                    }
                )

        return messages

    def build_incremental_messages(
        self, processed_width: int, processed_height: int
    ) -> List[Dict[str, Any]]:
        total_steps = len(self.screenshots)
        if total_steps < 1:
            raise RuntimeError("incremental messages require a current screenshot")

        current_b64 = self.screenshots[-1]
        current_uuid = self.screenshot_uuids[-1] if self.screenshot_uuids else None
        current_image = self._image_content(
            current_b64,
            include_bytes=True,
            image_uuid=current_uuid,
        )

        if total_steps == 1:
            instruction_prompt = (
                "\nPlease generate the next move according to the UI screenshot, "
                "instruction and previous actions.\n\n"
                f"Instruction: {self.task_description}\n\n"
                "Previous actions:\n"
                "None"
            )
            return [
                {
                    "role": "system",
                    "content": [
                        {
                            "type": "text",
                            "text": self._system_prompt(processed_width, processed_height),
                        }
                    ],
                },
                {
                    "role": "user",
                    "content": [
                        current_image,
                        {"type": "text", "text": instruction_prompt},
                    ],
                },
            ]

        messages: List[Dict[str, Any]] = []
        if self.incremental_include_assistant and self.responses:
            messages.append(
                {
                    "role": "assistant",
                    "content": [{"type": "text", "text": self.responses[-1]}],
                }
            )
        messages.append(
            {
                "role": "user",
                "content": self._wrap_tool_response([current_image]),
            }
        )
        return messages

    def step(self, obs, action_outputs):
        del action_outputs
        self.step_idx += 1

        step_timing: Dict[str, Any] = {}
        step_start = time.perf_counter()

        t0 = time.perf_counter()
        original_width, original_height = self._screen_size(obs["screen"])
        processed_image_b64, processed_path = self.process_image(obs["screen"])
        processed_width, processed_height = self._processed_size(processed_image_b64)
        self._remember_screenshot(processed_image_b64)
        self.b64_to_path[processed_image_b64] = processed_path
        step_timing["process_observation_ms"] = (time.perf_counter() - t0) * 1000.0

        t0 = time.perf_counter()
        if self.incremental_messages:
            messages = self.build_incremental_messages(processed_width, processed_height)
        else:
            messages = self.build_messages(processed_width, processed_height)
        step_timing["build_messages_ms"] = (time.perf_counter() - t0) * 1000.0

        t0 = time.perf_counter()
        self.save_messages(messages)
        step_timing["save_messages_ms"] = (time.perf_counter() - t0) * 1000.0

        if self.verbose:
            print(f"Calling Qwen3.5-VL with temperature: {self.temperature}")
        t0 = time.perf_counter()
        response = call_llm(
            messages,
            self.model,
            self.temperature,
            self.top_p,
            self.top_k,
            self.max_tokens,
            disable_thinking=self.disable_thinking,
            session_id=self.session_id if self.incremental_messages else None,
        )
        step_timing["llm_call_ms"] = (time.perf_counter() - t0) * 1000.0
        response = response or ""
        self.responses.append(response)

        t0 = time.perf_counter()
        parsed_response = self._parse_response(
            response,
            original_width=original_width,
            original_height=original_height,
            processed_width=processed_width,
            processed_height=processed_height,
        )
        step_timing["parse_response_ms"] = (time.perf_counter() - t0) * 1000.0

        t0 = time.perf_counter()
        actions = parsed_response["actions"]
        metadata = parsed_response["metadata"]
        self.all_model_responses.append(response)
        self.all_parsed_responses.append(parsed_response)
        self.history.append(metadata["conclusion"])

        if self.verbose:
            print(f"Step {self.step_idx + 1}:")
            print(f"  Conclusion: {metadata['conclusion']}")
            print(f"  Action Type: {metadata['action_type']}")
            print(f"  Actions: {actions}")

        step_timing["postprocess_ms"] = (time.perf_counter() - t0) * 1000.0
        step_timing["total_ms"] = (time.perf_counter() - step_start) * 1000.0
        step_timing["llm_response_chars"] = len(response)
        step_timing["actions_count"] = len(actions)
        step_timing["folded_prefix_k"] = self.folded_prefix_k
        self.last_step_timing = step_timing

        tool_id = f"qwen35_real_step_{self.step_idx}"
        if metadata["is_terminal"]:
            self.done = True
            return [{"tool_id": tool_id, "actions": actions, "metadata": metadata}]

        if metadata["wait_time"] is not None:
            return [
                {
                    "tool_id": tool_id,
                    "actions": [{"action": "wait", "time": metadata["wait_time"]}],
                    "metadata": metadata,
                }
            ]

        return [{"tool_id": tool_id, "actions": actions, "metadata": metadata}]

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

        conclusion = self._extract_action_line(body)
        actions: List[Dict[str, Any]] = []
        metadata: Dict[str, Any] = {
            "thought": response.split("</think>", 1)[0] if "</think>" in response else "",
            "conclusion": conclusion or "",
            "action_type": "screenshot",
            "is_terminal": False,
            "wait_time": None,
        }

        matches = list(self._TOOL_CALL_RE.finditer(body))
        if not matches:
            return self._empty_screenshot_action(
                conclusion or "Failed to parse Qwen3.5-VL XML tool call",
                parse_error=True,
            )

        for match in matches:
            action_json = self._parse_xml_tool_call(match.group(1))
            if action_json is None:
                continue
            parsed_actions, parsed_metadata = self._actions_from_json(
                action_json,
                original_width=original_width,
                original_height=original_height,
                processed_width=processed_width,
                processed_height=processed_height,
            )
            actions.extend(parsed_actions)
            metadata.update(parsed_metadata)

        if not actions and not metadata.get("is_terminal") and metadata.get("wait_time") is None:
            return self._empty_screenshot_action(
                conclusion or "No executable Qwen3.5-VL action parsed",
                parse_error=True,
            )

        if not metadata["conclusion"]:
            if metadata["is_terminal"]:
                metadata["conclusion"] = "Task completed"
            elif metadata["wait_time"] is not None:
                metadata["conclusion"] = "Waiting"
            else:
                metadata["conclusion"] = "Performing action"

        return {"actions": actions, "metadata": metadata}

    @staticmethod
    def _extract_action_line(response: str) -> Optional[str]:
        for line in response.split("\n"):
            stripped = line.strip()
            if stripped.lower().startswith("action:"):
                return stripped.split(":", 1)[-1].strip()
        return None

    def _parse_xml_tool_call(self, xml_content: str) -> Optional[Dict[str, Any]]:
        func_match = self._FUNCTION_RE.search(xml_content)
        if not func_match or func_match.group(1).strip() != "computer_use":
            return None

        params: Dict[str, Any] = {}
        for match in self._PARAMETER_RE.finditer(xml_content):
            name = match.group(1).strip()
            params[name] = self._coerce_value(match.group(2))
        if "action" not in params:
            return None
        return params

    @staticmethod
    def _coerce_value(raw: str) -> Any:
        value = raw.strip()
        if value.startswith("[") or value.startswith("{"):
            try:
                return json.loads(value)
            except json.JSONDecodeError:
                try:
                    return ast.literal_eval(value)
                except (ValueError, SyntaxError):
                    return value
        return value

    def _actions_from_json(
        self,
        action_json: Dict[str, Any],
        *,
        original_width: Optional[int],
        original_height: Optional[int],
        processed_width: Optional[int],
        processed_height: Optional[int],
    ) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
        action_type = str(action_json.get("action", "")).strip()
        metadata: Dict[str, Any] = {
            "action_type": action_type,
            "is_terminal": False,
            "wait_time": None,
        }
        actions: List[Dict[str, Any]] = []

        def adjust_coordinates(raw_coordinate) -> Optional[Tuple[int, int]]:
            coordinate = self._parse_coordinate(raw_coordinate)
            if coordinate is None:
                return None
            x, y = coordinate
            if not (original_width and original_height):
                return int(x), int(y)
            if self.coordinate_type == "absolute":
                if processed_width and processed_height:
                    return (
                        int(x * original_width / processed_width),
                        int(y * original_height / processed_height),
                    )
                return int(x), int(y)
            return int(x * original_width / 999), int(y * original_height / 999)

        coordinate = adjust_coordinates(action_json.get("coordinate"))
        modifier_keys = self._parse_modifier_keys(action_json.get("text"))

        def add_modifier_prefix() -> None:
            if modifier_keys:
                actions.append({"keyboard": {"keys": modifier_keys}})
                metadata["modifier_keys"] = modifier_keys
                metadata["modifier_note"] = (
                    "Gym Anything has no held-modifier click primitive; "
                    "modifier chord was emitted immediately before the mouse action."
                )

        if action_type == "key":
            actions.append({"keyboard": {"keys": self._parse_keys(action_json.get("keys", []))}})
        elif action_type == "type":
            actions.append({"keyboard": {"text": str(action_json.get("text", ""))}})
        elif action_type == "mouse_move":
            x, y = coordinate if coordinate is not None else (0, 0)
            actions.append({"mouse": {"move": [x, y]}})
        elif action_type in self._CLICK_ACTIONS:
            add_modifier_prefix()
            if coordinate is None:
                actions.extend(self._current_position_click_actions(action_type))
            else:
                x, y = coordinate
                if action_type == "left_click":
                    actions.append({"mouse": {"left_click": [x, y]}})
                elif action_type == "right_click":
                    actions.append({"mouse": {"right_click": [x, y]}})
                elif action_type == "middle_click":
                    actions.append({"mouse": {"middle_click": [x, y]}})
                elif action_type == "double_click":
                    actions.append({"mouse": {"double_click": [x, y]}})
                elif action_type == "triple_click":
                    actions.append({"mouse": {"triple_click": [x, y]}})
        elif action_type == "left_click_drag":
            x, y = coordinate if coordinate is not None else (0, 0)
            actions.extend(
                [
                    {"mouse": {"buttons": {"left_down": True}}},
                    {"mouse": {"move": [x, y]}},
                    {"mouse": {"buttons": {"left_up": True}}},
                ]
            )
        elif action_type in self._SCROLL_ACTIONS:
            add_modifier_prefix()
            if coordinate is not None:
                actions.append({"mouse": {"move": list(coordinate)}})
            actions.append({"mouse": {"scroll": self._parse_int(action_json.get("pixels", 0))}})
            if action_type == "hscroll":
                metadata["mapped_from"] = "hscroll"
        elif action_type == "wait":
            metadata["wait_time"] = self._parse_float(action_json.get("time", 1.0), 1.0)
        elif action_type == "terminate":
            metadata["is_terminal"] = True
            metadata["status"] = action_json.get("status", "success")
        elif action_type == "answer":
            metadata["is_terminal"] = True
            metadata["status"] = "success"
            metadata["answer"] = str(action_json.get("text", ""))

        return actions, metadata

    @staticmethod
    def _parse_coordinate(raw_coordinate) -> Optional[Tuple[float, float]]:
        if raw_coordinate is None:
            return None
        if isinstance(raw_coordinate, str):
            try:
                raw_coordinate = json.loads(raw_coordinate)
            except json.JSONDecodeError:
                try:
                    raw_coordinate = ast.literal_eval(raw_coordinate)
                except (ValueError, SyntaxError):
                    return None
        if isinstance(raw_coordinate, (list, tuple)) and len(raw_coordinate) >= 2:
            try:
                return float(raw_coordinate[0]), float(raw_coordinate[1])
            except (TypeError, ValueError):
                return None
        return None

    @staticmethod
    def _current_position_click_actions(action_type: str) -> List[Dict[str, Any]]:
        if action_type in {"left_click", "double_click", "triple_click"}:
            repeats = {"left_click": 1, "double_click": 2, "triple_click": 3}[action_type]
            return [
                action
                for _ in range(repeats)
                for action in (
                    {"mouse": {"buttons": {"left_down": True}}},
                    {"mouse": {"buttons": {"left_up": True}}},
                )
            ]
        if action_type == "right_click":
            return [
                {"mouse": {"buttons": {"right_down": True}}},
                {"mouse": {"buttons": {"right_up": True}}},
            ]
        if action_type == "middle_click":
            return [
                {"mouse": {"buttons": {"middle_down": True}}},
                {"mouse": {"buttons": {"middle_up": True}}},
            ]
        return []

    @classmethod
    def _parse_keys(cls, raw_keys) -> List[str]:
        if raw_keys is None:
            return []
        if isinstance(raw_keys, str):
            try:
                parsed = json.loads(raw_keys)
                raw_keys = parsed if isinstance(parsed, list) else [raw_keys]
            except json.JSONDecodeError:
                try:
                    parsed = ast.literal_eval(raw_keys)
                    raw_keys = parsed if isinstance(parsed, (list, tuple, set)) else [raw_keys]
                except (ValueError, SyntaxError):
                    raw_keys = re.split(r"[+,\s]+", raw_keys.strip("[]()"))
        elif isinstance(raw_keys, (tuple, set)):
            raw_keys = list(raw_keys)
        elif not isinstance(raw_keys, list):
            raw_keys = [raw_keys]

        keys = []
        for key in raw_keys:
            keys.extend(cls._split_key_tokens(str(key)))
        return keys

    @classmethod
    def _parse_modifier_keys(cls, value) -> List[str]:
        if not value:
            return []
        if isinstance(value, (list, tuple, set)):
            parts = value
        else:
            parts = re.split(r"[+,\s]+", str(value).strip("[]()"))
        keys = []
        for part in parts:
            keys.extend(cls._split_key_tokens(str(part)))
        return keys

    @classmethod
    def _split_key_tokens(cls, value: str) -> List[str]:
        keys = []
        text = value.strip().strip("[]()\"'").lower()
        for token in re.split(r"[+,\s]+", text):
            key = cls._normalize_key(token)
            if key:
                keys.append(key)
        return keys

    @staticmethod
    def _normalize_key(key: str) -> str:
        key = key.strip().strip("[]()\"'").lower()
        aliases = {
            "control": "ctrl",
            "command": "meta",
            "cmd": "meta",
            "option": "alt",
            "return": "enter",
            "esc": "escape",
        }
        return aliases.get(key, key)

    @staticmethod
    def _parse_float(value, default: float) -> float:
        try:
            return float(value)
        except (TypeError, ValueError):
            return default

    @classmethod
    def _parse_int(cls, value, default: int = 0) -> int:
        return int(cls._parse_float(value, float(default)))

    @staticmethod
    def _empty_screenshot_action(
        conclusion: str, *, parse_error: bool = False
    ) -> Dict[str, Any]:
        metadata: Dict[str, Any] = {
            "thought": "",
            "conclusion": conclusion,
            "action_type": "screenshot",
            "is_terminal": False,
            "wait_time": None,
        }
        if parse_error:
            metadata["parse_error"] = True
        return {"actions": [{"action": "screenshot"}], "metadata": metadata}

    def finish(self, *args, **kwargs):
        self._wait_for_image_saves()

        responses = {
            "model_responses": self.all_model_responses,
            "parsed_responses": self.all_parsed_responses,
            "history": self.history,
            "folded_prefix_k": self.folded_prefix_k,
        }
        with open(f"{self.save_path}/responses.json", "w", encoding="utf-8") as handle:
            json.dump(responses, handle, indent=4, ensure_ascii=False, default=str)
        with open(
            f"{self.save_path}/parsed_responses.json", "w", encoding="utf-8"
        ) as handle:
            json.dump(
                self.all_parsed_responses,
                handle,
                indent=4,
                ensure_ascii=False,
                default=str,
            )

        with open(
            f"{self.save_folder_custom}/responses.json", "w", encoding="utf-8"
        ) as handle:
            json.dump(responses, handle, indent=4, ensure_ascii=False, default=str)
        with open(
            f"{self.save_folder_custom}/parsed_responses.json", "w", encoding="utf-8"
        ) as handle:
            json.dump(
                self.all_parsed_responses,
                handle,
                indent=4,
                ensure_ascii=False,
                default=str,
            )

        if "info" in kwargs:
            with open(f"{self.save_folder_custom}/info.json", "w", encoding="utf-8") as handle:
                json.dump(kwargs["info"], handle, indent=4, ensure_ascii=False, default=str)


qwen35RealAgent = Qwen35RealAgent

__all__ = ["Qwen35RealAgent", "qwen35RealAgent"]
