import ast
import base64
import json
import math
import os
import re
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import backoff
import openai

try:
    from loguru import logger  # type: ignore
except ImportError:
    import logging

    logger = logging.getLogger(__name__)
    if not logger.handlers:
        handler = logging.StreamHandler()
        formatter = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
        handler.setFormatter(formatter)
        logger.addHandler(handler)
    logger.setLevel(logging.INFO)

from baselines.agents.base import BaseAgent
from baselines.common.llm_clients import call_llm as ga_call_llm

# -----------------------------------------------------------------------------
# Prompt loading helpers - Load from opencua_from_osworld.py to stay in sync
# -----------------------------------------------------------------------------

_OPENCUA_SOURCE = Path(__file__).resolve().parent.parent / "opencua_from_osworld.py"


def _load_prompt_from_source(name: str, fallback: Optional[str] = None) -> str:
    """Load prompts directly from the upstream implementation to stay in sync."""
    try:
        # Simply import from the source module
        import sys
        import importlib.util
        spec = importlib.util.spec_from_file_location("opencua_source", _OPENCUA_SOURCE)
        if spec and spec.loader:
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            return getattr(module, name, fallback or "")
    except Exception as exc:
        logger.warning(f"Could not load {name} from source, using fallback: {exc}")
    return fallback or ""


AGNET_SYS_PROMPT_L1 = _load_prompt_from_source(
    "AGNET_SYS_PROMPT_L1",
    "You are a GUI agent. You are given a task and a screenshot of the screen. You need to "
    "perform a series of pyautogui actions to complete the task.",
)
AGNET_SYS_PROMPT_L2 = _load_prompt_from_source(
    "AGNET_SYS_PROMPT_L2",
    "You are a GUI agent. You are given a task and a screenshot of the screen. You need to "
    "perform a series of pyautogui actions to complete the task.",
)
AGNET_SYS_PROMPT_L3 = _load_prompt_from_source(
    "AGNET_SYS_PROMPT_L3",
    "You are a GUI agent. You are given a task and a screenshot of the screen. You need to "
    "perform a series of pyautogui actions to complete the task.",
)

STEP_TEMPLATE = "# Step {step_num}:\n"
INSTRUTION_TEMPLATE = (
    "# Task Instruction:\n{instruction}\n\n"
    "Please generate the next move according to the screenshot, task instruction and previous steps (if provided).\n"
)

ACTION_HISTORY_TEMPLATE = "## Action:\n{action}\n"
THOUGHT_HISTORY_TEMPLATE = "## Thought:\n{thought}\n\n## Action:\n{action}\n"
OBSERVATION_HISTORY_TEMPLATE = "## Observation:\n{observation}\n\n## Thought:\n{thought}\n\n## Action:\n{action}\n"
DETAIL_HISTORY_TEMPLATE = "## Thought:\n{thought}\n\n## Action:\n{action}\n\n## Code:\n{code}\n"


# -----------------------------------------------------------------------------
# Utility helpers adapted from the upstream OpenCUA implementation
# -----------------------------------------------------------------------------

def encode_image(image_content: bytes) -> str:
    """Encode raw image bytes to base64."""
    return base64.b64encode(image_content).decode("utf-8")


def _safe_literal_eval(value):
    try:
        return ast.literal_eval(value)
    except Exception:
        return value


def correct_pyautogui_arguments(code: str) -> str:
    """Correct common pyautogui argument name mismatches."""
    function_corrections = {
        "write": {"incorrect_args": ["text", "content"], "keyword_arg": "message"},
        "press": {"incorrect_args": ["key", "button"], "keyword_arg": None},
        "hotkey": {"incorrect_args": ["key1", "key2", "keys"], "keyword_arg": None},
    }

    lines = code.strip().split("\n")
    corrected_lines = []

    for line in lines:
        line = line.strip()
        match = re.match(r"(pyautogui\.(\w+))\((.*)\)", line)
        if match:
            full_func_call = match.group(1)
            func_name = match.group(2)
            args_str = match.group(3)

            if func_name in function_corrections:
                func_info = function_corrections[func_name]
                args = split_args(args_str)
                corrected_args = []

                for arg in args:
                    arg = arg.strip()
                    kwarg_match = re.match(r"(\w+)\s*=\s*(.*)", arg)
                    if kwarg_match:
                        arg_name = kwarg_match.group(1)
                        arg_value = kwarg_match.group(2)

                        if arg_name in func_info["incorrect_args"]:
                            if func_info["keyword_arg"]:
                                corrected_args.append(f"{func_info['keyword_arg']}={arg_value}")
                            else:
                                corrected_args.append(arg_value)
                        else:
                            corrected_args.append(f"{arg_name}={arg_value}")
                    else:
                        corrected_args.append(arg)

                corrected_args_str = ", ".join(corrected_args)
                corrected_line = f"{full_func_call}({corrected_args_str})"
                corrected_lines.append(corrected_line)
            else:
                corrected_lines.append(line)
        else:
            corrected_lines.append(line)

    corrected_code = "\n".join(corrected_lines)
    return corrected_code


def split_args(args_str: str) -> List[str]:
    """Split the arguments string into a list of arguments."""
    args: List[str] = []
    current_arg = ""
    within_string = False
    string_char = ""
    prev_char = ""
    for char in args_str:
        if char in ['"', "'"]:
            if not within_string:
                within_string = True
                string_char = char
            elif within_string and prev_char != "\\" and char == string_char:
                within_string = False
        if char == "," and not within_string:
            args.append(current_arg)
            current_arg = ""
        else:
            current_arg += char
        prev_char = char
    if current_arg:
        args.append(current_arg)
    return args


def smart_resize(
    height: int,
    width: int,
    factor: int,
    min_pixels: int,
    max_pixels: int,
    max_aspect_ratio_allowed: Optional[float] = None,
    size_can_be_smaller_than_factor: bool = False,
) -> Tuple[int, int]:
    """
    Resize helper borrowed from Qwen2.5-VL utilities.
    Ensures divisibility by factor and stays within provided pixel limits.
    """
    if not size_can_be_smaller_than_factor and (height < factor or width < factor):
        raise ValueError(
            f"height:{height} or width:{width} must be larger than factor:{factor} "
            f"(when size_can_be_smaller_than_factor is False)"
        )
    if (
        max_aspect_ratio_allowed is not None
        and max(height, width) / min(height, width) > max_aspect_ratio_allowed
    ):
        raise ValueError(
            f"absolute aspect ratio must be smaller than {max_aspect_ratio_allowed}, "
            f"got {max(height, width) / min(height, width)}"
            f"(when max_aspect_ratio_allowed is not None)"
        )
    h_bar = max(1, round(height / factor)) * factor
    w_bar = max(1, round(width / factor)) * factor
    if h_bar * w_bar > max_pixels:
        beta = math.sqrt((height * width) / max_pixels)
        h_bar = max(1, math.floor(height / beta / factor)) * factor
        w_bar = max(1, math.floor(width / beta / factor)) * factor
    elif h_bar * w_bar < min_pixels:
        beta = math.sqrt(min_pixels / (height * width))
        h_bar = math.ceil(height * beta / factor) * factor
        w_bar = math.ceil(width * beta / factor) * factor
    return h_bar, w_bar


def _coordinate_projection(x, y, screen_width, screen_height, coordinate_type):
    """Project coordinates to absolute scale."""
    if coordinate_type == "relative":
        return int(round(x * screen_width)), int(round(y * screen_height))
    if coordinate_type == "absolute":
        return x, y
    if coordinate_type == "qwen25":
        if 0 <= x <= 1 and 0 <= y <= 1:
            return int(round(x * screen_width)), int(round(y * screen_height))
        height, width = smart_resize(
            height=screen_height,
            width=screen_width,
            factor=28,
            min_pixels=3136,
            max_pixels=12845056,
        )
        return int(x / width * screen_width), int(y / height * screen_height)
    raise ValueError(f"Unsupported coordinate type: {coordinate_type}")


def project_coordinate_to_absolute_scale(
    pyautogui_code_relative_coordinates, screen_width, screen_height, coordinate_type="relative"
):
    """Convert relative pyautogui coordinates to absolute ones."""
    if coordinate_type not in ["relative", "relative1000", "absolute", "qwen25"]:
        raise ValueError(
            f"Invalid coordinate type: {coordinate_type}. "
            "Expected one of ['relative', 'relative1000', 'absolute', 'qwen25']."
        )

    pattern = r"(pyautogui\.\w+\([^\)]*\))"
    matches = re.findall(pattern, pyautogui_code_relative_coordinates)

    new_code = pyautogui_code_relative_coordinates

    for full_call in matches:
        func_name_pattern = r"(pyautogui\.\w+)\((.*)\)"
        func_match = re.match(func_name_pattern, full_call, re.DOTALL)
        if not func_match:
            continue

        func_name = func_match.group(1)
        args_str = func_match.group(2)

        try:
            parsed = ast.parse(f"func({args_str})").body[0].value
            parsed_args = parsed.args
            parsed_keywords = parsed.keywords
        except SyntaxError:
            return pyautogui_code_relative_coordinates

        function_parameters = {
            "click": ["x", "y", "clicks", "interval", "button", "duration", "pause"],
            "moveTo": ["x", "y", "duration", "tween", "pause"],
            "moveRel": ["xOffset", "yOffset", "duration", "tween", "pause"],
            "dragTo": ["x", "y", "duration", "button", "mouseDownUp", "pause"],
            "dragRel": ["xOffset", "yOffset", "duration", "button", "mouseDownUp", "pause"],
            "doubleClick": ["x", "y", "interval", "button", "duration", "pause"],
        }

        func_base_name = func_name.split(".")[-1]

        param_names = function_parameters.get(func_base_name, [])

        args = {}
        for idx, arg in enumerate(parsed_args):
            if idx < len(param_names):
                param_name = param_names[idx]
                arg_value = ast.literal_eval(arg)
                args[param_name] = arg_value

        try:
            for kw in parsed_keywords:
                param_name = kw.arg
                arg_value = ast.literal_eval(kw.value)
                args[param_name] = arg_value
        except Exception as exc:
            logger.error(f"Error parsing keyword arguments: {exc}")
            return pyautogui_code_relative_coordinates

        updated = False
        if "x" in args and "y" in args:
            try:
                x_rel = float(args["x"])
                y_rel = float(args["y"])
                x_abs, y_abs = _coordinate_projection(
                    x_rel, y_rel, screen_width, screen_height, coordinate_type
                )
                logger.warning(
                    f"Projecting coordinates: ({x_rel}, {y_rel}) "
                    f"to ({x_abs}, {y_abs}) using {coordinate_type} projection."
                )
                args["x"] = x_abs
                args["y"] = y_abs
                updated = True
            except ValueError:
                pass

        if "xOffset" in args and "yOffset" in args:
            try:
                x_rel = float(args["xOffset"])
                y_rel = float(args["yOffset"])
                x_abs, y_abs = _coordinate_projection(
                    x_rel, y_rel, screen_width, screen_height, coordinate_type
                )
                args["xOffset"] = x_abs
                args["yOffset"] = y_abs
                updated = True
            except ValueError:
                pass

        if updated:
            reconstructed_args = []
            for idx, param_name in enumerate(param_names):
                if param_name in args:
                    arg_value = args[param_name]
                    if isinstance(arg_value, str):
                        arg_repr = f"'{arg_value}'"
                    else:
                        arg_repr = str(arg_value)
                    reconstructed_args.append(arg_repr)
                else:
                    break

            used_params = set(param_names[: len(reconstructed_args)])
            for kw in parsed_keywords:
                if kw.arg not in used_params:
                    arg_value = args[kw.arg]
                    if isinstance(arg_value, str):
                        arg_repr = f"{kw.arg}='{arg_value}'"
                    else:
                        arg_repr = f"{kw.arg}={arg_value}"
                    reconstructed_args.append(arg_repr)

            new_args_str = ", ".join(reconstructed_args)
            new_full_call = f"{func_name}({new_args_str})"
            new_code = new_code.replace(full_call, new_full_call)

    return new_code


def transform_agnet_action_to_code_block(action: str) -> str:
    """Transform the agent action to a code block for logging."""
    if "computer.terminate" in action or "browser.select_option" in action or "browser.clear" in action:
        return f"```code\n{action}\n```"
    return f"```python\n{action}\n```"


def parse_response_to_cot_and_action(input_string, screen_size, coordinate_type) -> Tuple[str, List[str], dict]:
    """Parse response including Observation, Thought, Action and code block."""
    try:
        sections: Dict[str, Any] = {}

        obs_match = re.search(
            r"^##\s*Observation\s*:?[\n\r]+(.*?)(?=^##\s*Thought:|^##\s*Action:|^##|\Z)",
            input_string,
            re.DOTALL | re.MULTILINE,
        )
        if obs_match:
            sections["observation"] = obs_match.group(1).strip()

        thought_match = re.search(
            r"^##\s*Thought\s*:?[\n\r]+(.*?)(?=^##\s*Action:|^##|\Z)",
            input_string,
            re.DOTALL | re.MULTILINE,
        )
        if thought_match:
            sections["thought"] = thought_match.group(1).strip()

        action_match = re.search(r"^##\s*Action\s*:?[\n\r]+(.*?)(?=^##|\Z)", input_string, re.DOTALL | re.MULTILINE)
        if action_match:
            action = action_match.group(1).strip()
            sections["action"] = action.strip()

        if "computer.terminate" in input_string.lower():
            code_blocks = re.findall(r"```(?:code|python)?\s*(.*?)\s*```", input_string, re.DOTALL | re.IGNORECASE)
            if code_blocks:
                last_code = code_blocks[-1].strip().lower()
                if "fail" in last_code:
                    sections["code"] = "FAIL"
                    return "FAIL", ["FAIL"], sections
                if "success" in last_code:
                    sections["code"] = "DONE"
                    return "DONE", ["DONE"], sections
            sections["code"] = "DONE"
            return "DONE", ["DONE"], sections

        code_blocks = re.findall(r"```(?:python)\s*(.*?)\s*```", input_string, re.DOTALL)
        if code_blocks:
            code = code_blocks[-1].strip()
            sections["original_code"] = transform_agnet_action_to_code_block(code)
            corrected_code = correct_pyautogui_arguments(code)
            sections["code"] = corrected_code
            sections["code"] = project_coordinate_to_absolute_scale(
                corrected_code, screen_width=screen_size[0], screen_height=screen_size[1], coordinate_type=coordinate_type
            )
        else:
            sections["code"] = "WAIT"
            return "WAIT", ["WAIT"], sections

        if "code" not in sections:
            logger.error("Missing required action or code section")
            return None, None, {}

        if "action" not in sections:
            sections["action"] = ""

        return sections["action"], [sections["code"]], sections
    except Exception as exc:
        logger.exception(f"Error parsing response: {str(exc)}\nInput string: {input_string}")
        return None, None, {}


# -----------------------------------------------------------------------------
# Agent implementation
# -----------------------------------------------------------------------------

class OpenCUAAgent(BaseAgent):
    """
    OpenCUA agent adapted for the Gym-Anything loop.

    It closely mirrors the upstream OSWorld implementation while emitting
    Gym-Anything compatible action dictionaries.
    """

    def __init__(self, *args, **kwargs):
        self.agent_args = kwargs.get("agent_args", {})
        self.model = self.agent_args.get("model", "opencua")
        self.history_type = self.agent_args.get("history_type", "observation_history")
        self.max_image_history_length = self.agent_args.get("max_image_history_length", 3)
        self.platform = self.agent_args.get("platform", "ubuntu")
        self.max_tokens = self.agent_args.get("max_tokens", 1500)
        self.top_p = self.agent_args.get("top_p", 0.9)
        self.temperature = self.agent_args.get("temperature", 0.0)
        self.action_space = "pyautogui"
        self.observation_type = "screenshot"
        self.cot_level = self.agent_args.get("cot_level", "l2")
        self.coordinate_type = self.agent_args.get("coordinate_type", "relative")
        self.default_wait_time = float(self.agent_args.get("default_wait_time", 1.0))

        self.exp_name = self.agent_args.get("exp_name", "exp")
        self.save_folder_custom: Optional[str] = None
        self._setup_custom_logger()

        if self.history_type not in ["action_history", "thought_history", "observation_history"]:
            raise ValueError(f"Invalid history type: {self.history_type}")

        if self.cot_level == "l3":
            self.SYSTEM_PROMPT = AGNET_SYS_PROMPT_L3
        elif self.cot_level == "l2":
            self.SYSTEM_PROMPT = AGNET_SYS_PROMPT_L2
        elif self.cot_level == "l1":
            self.SYSTEM_PROMPT = AGNET_SYS_PROMPT_L1
        else:
            raise ValueError(f"Invalid COT level: {self.cot_level}")

        history_templates = {
            "action_history": ACTION_HISTORY_TEMPLATE,
            "thought_history": THOUGHT_HISTORY_TEMPLATE,
            "observation_history": OBSERVATION_HISTORY_TEMPLATE,
        }
        self.HISTORY_TEMPLATE = history_templates[self.history_type]

        self.done = False
        self.step_idx = -1
        self.screen_size: Tuple[int, int] = (1920, 1080)
        self.last_mouse_pos: Optional[Tuple[int, int]] = None

        self.actions: List[str] = []
        self.observations: List[Dict[str, Any]] = []
        self.cots: List[Dict[str, Any]] = []
        self.history: List[str] = []
        self.all_model_responses: List[str] = []
        self.all_parsed_responses: List[Dict[str, Any]] = []

        self.debug = kwargs.get("debug", False)
        self.verbose = kwargs.get("verbose", False)

    # ------------------------------------------------------------------
    # LLM Call with Finish Reason Check
    # ------------------------------------------------------------------
    @backoff.on_exception(
        backoff.constant,
        (Exception),
        interval=30,
        max_tries=10
    )
    def _call_llm_with_finish_check(self, messages: List[Dict]) -> str:
        """
        Call LLM with finish reason validation, matching opencua_from_osworld.py behavior.
        Retries up to 30 times if finish_reason is not 'stop'.
        """
        client = openai.OpenAI(base_url="http://localhost:4243/v1", api_key="EMPTY")
        
        for attempt in range(30):
            try:
                response = client.chat.completions.create(
                    model=self.model,
                    messages=messages,
                    temperature=self.temperature,
                    top_p=self.top_p,
                    max_tokens=self.max_tokens,
                    extra_body={"repetition_penalty": 1.0, "top_k": -1},
                )
                
                finish_reason = response.choices[0].finish_reason
                if finish_reason is not None and finish_reason == "stop":
                    return response.choices[0].message.content
                else:
                    logger.warning(f"Attempt {attempt + 1}: finish_reason={finish_reason}, retrying...")
                    time.sleep(5)
            except Exception as e:
                logger.error(f"Attempt {attempt + 1}: LLM call failed: {e}")
                time.sleep(5)
        
        # If we exhausted all retries, raise an error
        raise RuntimeError("Failed to get valid LLM response after 30 attempts")

    # ------------------------------------------------------------------
    # Setup & IO helpers
    # ------------------------------------------------------------------
    def _setup_custom_logger(self) -> None:
        """Create a custom folder to store artifacts."""
        task_name = self.agent_args.get("task_name", "task")
        base_dir = Path("all_runs") / self.exp_name / self.model / task_name
        for run_number in range(0, 100):
            candidate = base_dir / f"run_{run_number}"
            if candidate.exists():
                continue
            self.save_folder_custom = str(candidate)
            break
        if self.save_folder_custom:
            Path(self.save_folder_custom).mkdir(parents=True, exist_ok=False)

    def _save_observation(self, observation_path: str) -> bytes:
        """Persist the screenshot for debugging and return raw bytes."""
        raw = Path(observation_path).read_bytes()
        if self.save_folder_custom is not None:
            target = Path(self.save_folder_custom) / f"observation_{self.step_idx}.png"
            Path(observation_path).replace(target)
            raw = target.read_bytes()
        return raw

    def init(self, task_description: str, display_resolution: Tuple[int, int], save_path: str):
        self.task_description = task_description
        self.display_resolution = display_resolution
        self.screen_size = display_resolution
        self.save_path = save_path
        self.last_mouse_pos = (display_resolution[0] / 2, display_resolution[1] / 2)

    def _scale_scroll_for_windows(self, code: str, factor: int = 50) -> str:
        """pyautogui.scroll has different scale on Ubuntu and Windows."""
        if self.platform.lower() != "windows":
            return code
        pattern_pos = re.compile(r"(pyautogui\.scroll\()\s*([-+]?\d+)\s*\)")
        return pattern_pos.sub(lambda m: f"{m.group(1)}{int(m.group(2)) * factor})", code)

    def predict(self, instruction: str, obs: Dict[str, Any], **kwargs) -> Tuple[str, List[str], Dict[str, Any]]:
        """Predict the next pyautogui code block using the OpenCUA API."""
        if "step_idx" in kwargs:
            logger.info(f"========= {self.model} Step {kwargs['step_idx']} =======")
        else:
            logger.info(f"========================== {self.model} ===================================")
        logger.info(f"Instruction: \n{instruction}")

        messages: List[Dict[str, Any]] = []
        messages.append({"role": "system", "content": self.SYSTEM_PROMPT})

        history_step_texts: List[str] = []
        for i in range(len(self.actions)):
            if i > len(self.actions) - self.max_image_history_length:
                messages.append(
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "image_url",
                                "image_url": {"url": f"data:image/png;base64,{encode_image(self.observations[i]['screenshot'])}"},
                            }
                        ],
                    }
                )

                history_content = STEP_TEMPLATE.format(step_num=i + 1) + self.HISTORY_TEMPLATE.format(
                    observation=self.cots[i].get("observation"),
                    thought=self.cots[i].get("thought"),
                    action=self.cots[i].get("action"),
                )

                messages.append({"role": "assistant", "content": history_content})
            else:
                history_content = STEP_TEMPLATE.format(step_num=i + 1) + self.HISTORY_TEMPLATE.format(
                    observation=self.cots[i].get("observation"),
                    thought=self.cots[i].get("thought"),
                    action=self.cots[i].get("action"),
                )
                history_step_texts.append(history_content)
                if i == len(self.actions) - self.max_image_history_length:
                    messages.append({"role": "assistant", "content": "\n".join(history_step_texts)})

        messages.append(
            {
                "role": "user",
                "content": [
                    {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{encode_image(obs['screenshot'])}"}},
                    {"type": "text", "text": INSTRUTION_TEMPLATE.format(instruction=instruction)},
                ],
            }
        )

        response = self._call_llm_with_finish_check(messages)

        logger.info(f"Model Output: \n{response}")
        if not response:
            logger.error("No response found in the response.")
            return "ERROR", ["FAIL"], {}

        low_level_instruction, pyautogui_actions, other_cot = parse_response_to_cot_and_action(
            response, self.screen_size, self.coordinate_type
        )
        if not pyautogui_actions or len(pyautogui_actions) == 0:
            logger.error("No pyautogui actions found in the response.")
            return response, ["FAIL"], {}

        pyautogui_actions = [self._scale_scroll_for_windows(code) for code in pyautogui_actions]

        self.observations.append(obs)
        logger.info(f"Parsed Low-level Action: \n{low_level_instruction}")
        logger.info(f"Parsed pyautogui Action: \n{pyautogui_actions}")

        self.actions.append(low_level_instruction or "")
        if "action" not in other_cot or not other_cot.get("action") or "thought" not in other_cot or not other_cot.get("thought"):
            logger.error("Error! no action/thought in cot")
            logger.error(f"response: {response}")
            logger.error(f"cot: {other_cot}")
        self.cots.append(other_cot)

        logger.info(f"New step cot: {other_cot}")

        return response, pyautogui_actions, other_cot

    # ------------------------------------------------------------------
    # Action conversion helpers
    # ------------------------------------------------------------------
    def _parse_pyautogui_call(self, line: str) -> Optional[Tuple[str, List[Any], Dict[str, Any]]]:
        line = line.strip()
        match = re.match(r"pyautogui\.(\w+)\((.*)\)", line)
        if not match:
            return None
        func = match.group(1)
        args_str = match.group(2)
        try:
            parsed = ast.parse(f"f({args_str})").body[0].value
        except SyntaxError:
            return None
        pos_args = [_safe_literal_eval(ast.get_source_segment(f"f({args_str})", arg)) for arg in parsed.args]
        kw_args = {kw.arg: _safe_literal_eval(ast.get_source_segment(f"f({args_str})", kw.value)) for kw in parsed.keywords}
        return func, pos_args, kw_args

    def _pyautogui_code_to_actions(self, code: str) -> List[Dict[str, Any]]:
        """Convert pyautogui code into Gym-Anything action dictionaries."""
        actions: List[Dict[str, Any]] = []
        for raw_line in code.splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            parsed = self._parse_pyautogui_call(line)
            if not parsed:
                logger.debug(f"Skipping unparsable line: {line}")
                continue
            func, pos_args, kw_args = parsed
            func_lower = func.lower()

            def _get_xy(default_x=None, default_y=None):
                x = kw_args.get("x", pos_args[0] if len(pos_args) > 0 else default_x)
                y = kw_args.get("y", pos_args[1] if len(pos_args) > 1 else default_y)
                return x, y

            if func_lower in ["click", "singleclick"]:
                x, y = _get_xy()
                if x is None or y is None:
                    continue
                button = str(kw_args.get("button", "left")).lower()
                clicks = kw_args.get("clicks", pos_args[2] if len(pos_args) > 2 else 1)
                self.last_mouse_pos = (x, y)
                if clicks and clicks >= 3:
                    actions.append({"mouse": {"triple_click": [x, y]}})
                elif clicks and clicks == 2:
                    actions.append({"mouse": {"double_click": [x, y]}})
                elif button == "right":
                    actions.append({"mouse": {"right_click": [x, y]}})
                else:
                    actions.append({"mouse": {"left_click": [x, y]}})
            elif func_lower in ["doubleclick", "double_click"]:
                x, y = _get_xy()
                if x is None or y is None:
                    continue
                self.last_mouse_pos = (x, y)
                actions.append({"mouse": {"double_click": [x, y]}})
            elif func_lower in ["tripleclick", "triple_click"]:
                x, y = _get_xy()
                if x is None or y is None:
                    continue
                self.last_mouse_pos = (x, y)
                actions.append({"mouse": {"triple_click": [x, y]}})
            elif func_lower == "moveto":
                x, y = _get_xy()
                if x is None or y is None:
                    continue
                self.last_mouse_pos = (x, y)
                actions.append({"mouse": {"move": [x, y]}})
            elif func_lower in ["dragto", "dragrel"]:
                x, y = _get_xy()
                if x is None or y is None:
                    continue
                start = self.last_mouse_pos or (x, y)
                button = str(kw_args.get("button", "left")).lower()
                key = "left_click_drag" if button.startswith("left") else "right_click_drag"
                actions.append({"mouse": {key: [[start[0], start[1]], [x, y]]}})
                self.last_mouse_pos = (x, y)
            elif func_lower == "scroll":
                amount = kw_args.get("clicks", kw_args.get("y", pos_args[0] if pos_args else 0))
                x_coord = kw_args.get("x")
                y_coord = kw_args.get("y") if "y" in kw_args else None
                if x_coord is not None and y_coord is not None:
                    actions.append({"mouse": {"move": [x_coord, y_coord]}})
                actions.append({"mouse": {"scroll": amount}})
            elif func_lower in ["write", "typewrite", "type"]:
                text = kw_args.get("message", kw_args.get("text", pos_args[0] if pos_args else ""))
                if text is not None:
                    actions.append({"keyboard": {"text": str(text)}})
            elif func_lower in ["press", "keydown", "keyup"]:
                key_val = kw_args.get("keys", kw_args.get("key", pos_args[0] if pos_args else None))
                if key_val is not None:
                    if isinstance(key_val, list):
                        keys = [str(k) for k in key_val]
                    else:
                        keys = [str(key_val)]
                    actions.append({"keyboard": {"keys": keys}})
            elif func_lower == "hotkey":
                keys = [str(k) for k in pos_args]
                if "keys" in kw_args:
                    extra_keys = kw_args["keys"]
                    if isinstance(extra_keys, list):
                        keys.extend([str(k) for k in extra_keys])
                    else:
                        keys.append(str(extra_keys))
                actions.append({"keyboard": {"keys": keys}})
            else:
                logger.warning(f"Unhandled pyautogui function: {func}")
        return actions

    # ------------------------------------------------------------------
    # Gym-Anything Agent API
    # ------------------------------------------------------------------
    def step(self, obs: Dict[str, Any], action_outputs: List[Dict[str, Any]]):
        screenshot_path = obs["screen"]["path"]
        self.step_idx += 1

        # Save and load screenshot bytes for the LLM call
        screenshot_bytes = Path(screenshot_path).read_bytes()
        if self.save_folder_custom is not None:
            target = Path(self.save_folder_custom) / f"observation_{self.step_idx}.png"
            Path(target).write_bytes(screenshot_bytes)

        response, pyautogui_actions, parsed = self.predict(
            self.task_description, {"screenshot": screenshot_bytes}, step_idx=self.step_idx
        )
        self.all_model_responses.append(response)
        self.all_parsed_responses.append(parsed)
        self.history.append(parsed.get("action", "") if isinstance(parsed, dict) else "")

        # Handle special actions
        metadata = {
            "thought": parsed.get("thought") if isinstance(parsed, dict) else None,
            "conclusion": parsed.get("action") if isinstance(parsed, dict) else None,
            "is_terminal": False,
            "wait_time": None,
        }

        if pyautogui_actions == ["DONE"] or pyautogui_actions == ["FAIL"]:
            self.done = True
            metadata["is_terminal"] = True
            gym_actions: List[Dict[str, Any]] = []
        elif pyautogui_actions == ["WAIT"]:
            gym_actions = []
            metadata["wait_time"] = self.default_wait_time
        else:
            gym_actions = []
            for code in pyautogui_actions:
                gym_actions.extend(self._pyautogui_code_to_actions(code))

        tool_id = f"opencua_step_{self.step_idx}"

        if metadata["wait_time"] is not None:
            return [
                {
                    "tool_id": tool_id,
                    "actions": [{"action": "wait", "time": metadata["wait_time"]}],
                    "metadata": metadata,
                }
            ]

        return [{"tool_id": tool_id, "actions": gym_actions, "metadata": metadata}]

    def finish(self, *args, **kwargs):
        """Persist agent artifacts."""
        if not hasattr(self, "save_path") or not self.save_path:
            return
        Path(self.save_path).mkdir(parents=True, exist_ok=True)
        payload = {
            "model_responses": self.all_model_responses,
            "parsed_responses": self.all_parsed_responses,
            "history": self.history,
        }
        with open(Path(self.save_path) / "opencua_responses.json", "w") as f:
            json.dump(payload, f, indent=4)
        if self.save_folder_custom:
            Path(self.save_folder_custom).mkdir(parents=True, exist_ok=True)
            with open(Path(self.save_folder_custom) / "opencua_responses.json", "w") as f:
                json.dump(payload, f, indent=4)
            if "info" in kwargs:
                with open(Path(self.save_folder_custom) / "info.json", "w") as f:
                    json.dump(kwargs["info"], f, indent=4)
