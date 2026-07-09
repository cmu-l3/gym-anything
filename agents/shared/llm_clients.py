from __future__ import annotations

import json
import logging
import os
import pickle
import time
import uuid

import litellm
import openai
from anthropic import Anthropic
from dotenv import load_dotenv
from openai import OpenAI

from agents.shared.prompts import CLAUDE_SYSTEM_PROMPT

load_dotenv()

LOG_DUMPS = "log_dumps_claude"
logger = logging.getLogger(__name__)


class _DisableThinkingViolation(RuntimeError):
    pass


def _env_flag_enabled(name: str) -> bool:
    value = os.environ.get(name)
    if value is None:
        return False
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _openai_extra_body(
    *,
    top_k: int,
    repetition_penalty: float,
    disable_thinking: bool,
    session_id: str | None = None,
) -> dict:
    extra_body = {"repetition_penalty": repetition_penalty, "top_k": top_k}
    if disable_thinking:
        extra_body["chat_template_kwargs"] = {"enable_thinking": False}
    if session_id:
        extra_body["session_id"] = session_id
    return extra_body


def _dump_usage(prefix: str, model: str, usage) -> None:
    try:
        os.makedirs(prefix, exist_ok=True)
        with open(f"{prefix}/{uuid.uuid4()}_{model}.pkl", "wb") as handle:
            pickle.dump(usage, handle)
    except Exception as exc:
        print(f"Error dumping usage: {exc}")


def call_kimi_azure(
    messages,
    model,
    temperature,
    top_p,
    top_k=-1,
    max_tokens=4096,
    repetition_penalty=1.0,
    return_full_response=False,
    max_attempts=10,
):
    del top_k, max_tokens, repetition_penalty
    client = OpenAI(
        base_url="https://claudefoundary.services.ai.azure.com/openai/v1/",
        api_key=os.getenv("KIMI_API_KEY"),
    )

    for attempt in range(max_attempts):
        try:
            response = client.chat.completions.create(
                model=model,
                messages=messages,
                temperature=temperature,
                top_p=top_p,
            )
            _dump_usage("model_usage_dumps", model, response.usage)
            if return_full_response:
                return response

            reasoning_content = getattr(response.choices[0].message, "reasoning_content", None)
            if reasoning_content:
                return f"<think>{reasoning_content}</think>\n{response.choices[0].message.content}"
            return response.choices[0].message.content
        except Exception as exc:
            print(f"Error calling kimi azure (attempt {attempt + 1}/{max_attempts}): {exc}")
            time.sleep(2 ** (attempt + 1))

    raise RuntimeError(f"Failed to get response from Kimi Azure after {max_attempts} attempts")


def call_llm(
    messages,
    model,
    temperature,
    top_p,
    top_k=-1,
    max_tokens=4096,
    repetition_penalty=1.0,
    disable_thinking=None,
    session_id=None,
):
    if disable_thinking is None:
        disable_thinking = _env_flag_enabled("VLM_DISABLE_THINKING")
    for attempt in range(10):
        try:
            logger.debug("Calling local OpenAI-compatible model: %s", model)
            client = openai.OpenAI(
                base_url=os.environ.get("VLM_BASE_URL", "http://localhost:8080/v1"),
                api_key="EMPTY",
            )
            response = client.chat.completions.create(
                model=model,
                messages=messages,
                temperature=temperature,
                top_p=top_p,
                extra_body=_openai_extra_body(
                    top_k=top_k,
                    repetition_penalty=repetition_penalty,
                    disable_thinking=bool(disable_thinking),
                    session_id=session_id,
                ),
                max_tokens=max_tokens,
            )
            logger.debug("Raw response from local LLM: %s", response)

            message = response.choices[0].message
            reasoning_content = getattr(message, "reasoning", None) or getattr(message, "reasoning_content", None)
            content = message.content
            if disable_thinking and reasoning_content:
                raise _DisableThinkingViolation(
                    "VLM_DISABLE_THINKING requested, but the model response included reasoning content"
                )
            if disable_thinking and content and "<think" in str(content).lower():
                raise _DisableThinkingViolation(
                    "VLM_DISABLE_THINKING requested, but the model response content included a <think> block"
                )

            if model in {"Qwen/Qwen3.5-397B-A17B", "Qwen/Qwen3.5-122B-A10B"}:
                if reasoning_content:
                    return f"<think>{reasoning_content}</think>\n{content}"
            return content
        except _DisableThinkingViolation:
            raise
        except openai.BadRequestError:
            raise
        except Exception as exc:
            print(f"Error calling llm (attempt {attempt + 1}/10): {exc}")
            time.sleep(2 ** (attempt + 1))

    raise RuntimeError("Failed to get response from LLM after 10 attempts")


def call_gemini_with_retry(
    messages,
    model,
    temperature,
    top_p,
    top_k=-1,
    max_tokens=16384,
    reasoning_effort="high",
    timeout=600,
    return_full_response=False,
):
    del top_k
    for attempt in range(5):
        try:
            response = litellm.completion(
                model="gemini/" + model,
                messages=messages,
                temperature=temperature,
                top_p=top_p,
                max_tokens=max_tokens,
                reasoning_effort=reasoning_effort,
                timeout=timeout,
            )
            _dump_usage("model_usage_dumps", model, response.usage)
            if return_full_response:
                return response

            reasoning_content = getattr(response.choices[0].message, "reasoning_content", None)
            content = response.choices[0].message.content
            if not content or not str(content).strip():
                print("All tokens taken by reasoning, retrying again")
                continue
            if reasoning_content:
                return f"<think>{reasoning_content}</think>\n{content}"
            return content
        except Exception as exc:
            print(f"Error calling gemini (attempt {attempt + 1}/5): {exc}")
            time.sleep(2 ** (attempt + 1))

    raise RuntimeError("Failed to get response from Gemini after 5 attempts")


def call_claude_with_retry(
    client,
    model,
    max_tokens,
    messages,
    system_prompt,
    tools,
    beta_flag,
    temperature,
    retries=5,
    **kwargs,
):
    response = None
    for attempt in range(retries):
        try:
            response = client.beta.messages.create(
                model=model,
                max_tokens=max_tokens,
                messages=messages,
                system=system_prompt,
                tools=tools,
                betas=[beta_flag],
                temperature=temperature,
                **kwargs,
            )
            print(response.usage)
            break
        except Exception as exc:
            print(f"Error calling claude: {exc}")
            time.sleep(2 ** (attempt + 1))

    if response is None:
        raise RuntimeError("Failed to get response from Claude")
    return response


# Models that support the 2025-11-24 computer-use beta and computer_20251124
# tool schema. Anything else falls back to the 2025-01-24 stack.
_NEW_COMPUTER_USE_MODELS = ("opus-4-5", "opus-4-6", "opus-4-7", "sonnet-4-6")

# Models whose API rejects the legacy `thinking.type.enabled` + `budget_tokens`
# pair and instead require `thinking.type.adaptive` + `output_config.effort`.
# Currently confirmed for the 4.7 family. 4.6 still accepts the legacy form.
_ADAPTIVE_THINKING_MODELS = ("opus-4-7", "sonnet-4-7", "haiku-4-7")


def _pick_computer_tool_version(model: str) -> tuple[str, str]:
    """Return (tool_type, beta_flag) appropriate for the requested model."""
    if any(tag in model for tag in _NEW_COMPUTER_USE_MODELS):
        return "computer_20251124", "computer-use-2025-11-24"
    return "computer_20250124", "computer-use-2025-01-24"


def _uses_adaptive_thinking(model: str) -> bool:
    return any(tag in model for tag in _ADAPTIVE_THINKING_MODELS)


def _budget_to_effort(budget: int) -> str:
    """Map legacy thinking_budget tokens to the new effort tiers.

    Anthropic's computer-use guidance recommends `high` as the default for
    Opus 4.7. Callers that pass a smaller budget get scaled down accordingly.
    """
    if budget <= 0:
        return "low"
    if budget <= 4096:
        return "low"
    if budget <= 12000:
        return "medium"
    return "high"


def call_claude(
    messages,
    model,
    temperature,
    top_p,
    thinking_budget=8192,
    system_prompt=CLAUDE_SYSTEM_PROMPT,
    use_all_tools=False,
    use_no_tools=False,
):
    del top_p
    client = Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))
    tool_type, beta_flag = _pick_computer_tool_version(model)
    # Declare the dims we actually SEND (resized 1280x720) rather than the
    # native env display (1920x1080). Anthropic's published guidance for 16:9
    # sources is to resize before sending; we then scale Claude's coordinates
    # back up to the env's native resolution via convert_point_format_claude.
    # Cuts image token cost roughly in half compared with sending native.
    tools = [
        {
            "type": tool_type,
            "name": "computer",
            "display_width_px": 1280,
            "display_height_px": 720,
        },
        {"type": "bash_20250124", "name": "bash"},
    ][: 1 if not use_all_tools else None]

    if thinking_budget == -1:
        kwargs = {}
    elif _uses_adaptive_thinking(model):
        # Opus/Sonnet/Haiku 4.7 reject the legacy thinking.type.enabled +
        # budget_tokens form and require adaptive thinking + an effort tier.
        # See https://platform.claude.com/docs/en/build-with-claude/extended-thinking
        # Anthropic's guidance for computer-use on Opus 4.7 is "high" as the
        # default; we derive the effort from the requested thinking_budget so
        # callers can still tune cost/quality the same way as before.
        kwargs = {
            "thinking": {"type": "adaptive"},
            "extra_body": {"output_config": {"effort": _budget_to_effort(thinking_budget)}},
        }
    else:
        kwargs = {"thinking": {"type": "enabled", "budget_tokens": thinking_budget}}
    response = call_claude_with_retry(
        client,
        model,
        16384,
        messages,
        system_prompt,
        tools if not use_no_tools else [],
        beta_flag,
        temperature,
        **kwargs,
    )

    try:
        os.makedirs(LOG_DUMPS, exist_ok=True)
        with open(f"{LOG_DUMPS}/{uuid.uuid4()}.pkl", "wb") as handle:
            pickle.dump(response, handle)
    except Exception as exc:
        print(f"Error dumping response: {exc}")

    return response


# The Qwen/Kimi computer-use parser lives in agents/shared/qwen_computer_use.py; re-exported here
# so existing `from agents.shared.llm_clients import ...` call sites keep working.
from agents.shared.qwen_computer_use import (  # noqa: E402,F401
    convert_point_format_qwen3vl,
    parse_qwen3vl_response,
)


def convert_point_format_claude(x, y):
    return int(x * 1920 / 1280), int(y * 1080 / 720)


def claude_parse_tool_result(action_json, coord_scale=convert_point_format_claude):
    """Translate one Claude computer-use tool_use into the wire actions the env runner expects.

    `coord_scale(x, y)` maps a coordinate from Claude's image space into the
    native screen space. Default matches the legacy 1280x720 -> 1920x1080 path
    so existing callers are unchanged; new callers (e.g. ClaudeFixedAgent that
    sends native-resolution screenshots) can pass an identity function.
    """

    # Bash tool result (only fires when bash tool is enabled at call_claude time).
    if "command" in action_json:
        return [{"action": "bash", "command": action_json["command"]}]

    action = action_json.get("action")

    # Pure observation actions.
    if action == "screenshot":
        return [{"action": "screenshot"}]
    if action == "cursor_position":
        # The env wire protocol has no cursor-position primitive; return a
        # screenshot so the model can read the cursor visually rather than
        # have the call silently dropped.
        return [{"action": "screenshot"}]
    if action == "zoom":
        # computer_20251124 zoom is not implemented locally; fall back to a
        # plain screenshot so the model still gets visual feedback.
        return [{"action": "screenshot"}]

    # Keyboard.
    if action == "key":
        keys = action_json.get("text", action_json.get("keys"))
        return [{"keyboard": {"keys": keys}}] if keys else []
    if action == "type":
        text = action_json.get("text", "")
        return [{"keyboard": {"text": text}}] if text else []
    if action == "hold_key":
        keys = action_json.get("text") or action_json.get("keys")
        duration = float(action_json.get("duration", 1.0))
        if not keys:
            return []
        keys_list = [keys] if isinstance(keys, str) else list(keys)
        return [
            {"keyboard": {"keys_down": keys_list}},
            {"action": "wait", "time": duration},
            {"keyboard": {"keys_up": keys_list}},
        ]

    # Fine-grained mouse buttons.
    if action == "left_mouse_down":
        return [{"mouse": {"buttons": {"left_down": True}}}]
    if action == "left_mouse_up":
        return [{"mouse": {"buttons": {"left_up": True}}}]

    if action == "mouse_move":
        x, y = coord_scale(action_json["coordinate"][0], action_json["coordinate"][1])
        return [{"mouse": {"move": [x, y]}}]

    if action == "wait":
        # Emit the env's recognised control-action shape ({"action":"wait","time":...}).
        # The previous shape ({"wait":{...}}) was a silent no-op.
        seconds = float(action_json.get("duration", action_json.get("time", 1.0)))
        return [{"action": "wait", "time": seconds}]

    # Click/scroll family. Per the official spec, these can carry a `text`
    # field naming a modifier key (shift/ctrl/alt/super) that must be held
    # for the duration of the click/scroll. We expand it as
    # [keys_down] + click + [keys_up] so the modifier is held end-to-end.
    modifier = action_json.get("text") if action in {
        "left_click", "click", "right_click", "middle_click",
        "double_click", "triple_click", "scroll",
        "left_click_drag", "drag",
    } else None

    def _wrap(inner):
        if not modifier:
            return inner
        mod_list = [modifier] if isinstance(modifier, str) else list(modifier)
        return (
            [{"keyboard": {"keys_down": mod_list}}]
            + inner
            + [{"keyboard": {"keys_up": mod_list}}]
        )

    if action in {"left_click", "click"}:
        x, y = coord_scale(action_json["coordinate"][0], action_json["coordinate"][1])
        return _wrap([{"mouse": {"left_click": [x, y]}}])
    if action == "right_click":
        x, y = coord_scale(action_json["coordinate"][0], action_json["coordinate"][1])
        return _wrap([{"mouse": {"right_click": [x, y]}}])
    if action == "middle_click":
        x, y = coord_scale(action_json["coordinate"][0], action_json["coordinate"][1])
        return _wrap([{"mouse": {"middle_click": [x, y]}}])
    if action == "double_click":
        x, y = coord_scale(action_json["coordinate"][0], action_json["coordinate"][1])
        return _wrap([{"mouse": {"double_click": [x, y]}}])
    if action == "triple_click":
        x, y = coord_scale(action_json["coordinate"][0], action_json["coordinate"][1])
        return _wrap([{"mouse": {"triple_click": [x, y]}}])

    if action in {"left_click_drag", "drag"}:
        if "start_coordinate" in action_json:
            x1, y1 = coord_scale(action_json["start_coordinate"][0], action_json["start_coordinate"][1])
            if "coordinate" in action_json:
                x2, y2 = coord_scale(action_json["coordinate"][0], action_json["coordinate"][1])
            elif "end_coordinate" in action_json:
                x2, y2 = coord_scale(action_json["end_coordinate"][0], action_json["end_coordinate"][1])
            else:
                x2, y2 = x1, y1
        else:
            x1, y1 = coord_scale(action_json["coordinate"][0], action_json["coordinate"][1])
            x2, y2 = coord_scale(action_json["coordinate2"][0], action_json["coordinate2"][1])
        return _wrap([
            {"mouse": {"move": [x1, y1]}},
            {"mouse": {"buttons": {"left_down": True}}},
            {"mouse": {"move": [x2, y2]}},
            {"mouse": {"buttons": {"left_up": True}}},
        ])

    if action == "scroll":
        direction = action_json.get("scroll_direction", "down")
        # Official spec uses scroll_amount; legacy callers may still pass pixels/scroll.
        amount = int(action_json.get(
            "scroll_amount",
            action_json.get("pixels", action_json.get("scroll", 3)),
        ))
        if direction == "up":
            dy = -amount
        elif direction == "down":
            dy = amount
        else:
            # left/right have no env primitive; default to vertical so the
            # call is not a silent no-op.
            dy = amount
        inner = []
        if "coordinate" in action_json:
            x, y = coord_scale(action_json["coordinate"][0], action_json["coordinate"][1])
            inner.append({"mouse": {"move": [x, y]}})
        inner.append({"mouse": {"scroll": dy}})
        return _wrap(inner)

    return []


def smart_resize(height, width, factor=32, max_pixels=16 * 16 * 4 * 1280):
    del factor, max_pixels
    return height, width


# ---------------------------------------------------------------------------
# GPT-5.x computer use (OpenAI Responses API, native `computer` tool)
# ---------------------------------------------------------------------------

# OpenAI's computer-use models emit uppercase key names (ENTER, CTRL,
# ARROWUP, ...); the env layer wants xdotool-style keysyms (Return, ctrl,
# Up, ...). Single characters and unknown names pass through lowercased on
# the letter path so chords like CTRL+A become ctrl+a.
_GPT_CU_KEYMAP = {
    "ENTER": "Return", "RETURN": "Return", "TAB": "Tab",
    "ESC": "Escape", "ESCAPE": "Escape", "BACKSPACE": "BackSpace",
    "DELETE": "Delete", "DEL": "Delete", "SPACE": "space",
    "CTRL": "ctrl", "CONTROL": "ctrl", "ALT": "alt", "OPTION": "alt",
    "SHIFT": "shift", "META": "super", "CMD": "super", "COMMAND": "super",
    "WIN": "super", "SUPER": "super",
    "ARROWUP": "Up", "ARROWDOWN": "Down", "ARROWLEFT": "Left",
    "ARROWRIGHT": "Right", "UP": "Up", "DOWN": "Down", "LEFT": "Left",
    "RIGHT": "Right",
    "PAGEUP": "Prior", "PAGEDOWN": "Next", "HOME": "Home", "END": "End",
    "INSERT": "Insert", "CAPSLOCK": "Caps_Lock", "PRINTSCREEN": "Print",
}


def convert_gpt_key(key):
    """Map an OpenAI computer-use key name to the env's xdotool-style name."""
    k = str(key).strip()
    mapped = _GPT_CU_KEYMAP.get(k.upper())
    if mapped:
        return mapped
    if k.upper().startswith("F") and k[1:].isdigit():
        return k.upper()  # F1..F12
    if len(k) == 1 and k.isalpha():
        return k.lower()
    return k


def call_gpt54_computer_use(
    client,
    model,
    tools,
    input_items,
    previous_response_id=None,
    compaction_threshold=None,
):
    """Call the OpenAI Responses API with the native computer tool.

    ``compaction_threshold`` enables server-side compaction
    (context_management type 'compaction'): when the rendered token count
    crosses the threshold the server folds prior state into a compaction
    item. Passed through extra_body so the call works on SDK versions that
    predate the typed parameter.
    """
    kwargs = {
        "model": model,
        "tools": tools,
        "input": input_items,
        # Surface reasoning summaries so the agent can log the model's
        # thinking alongside each action.
        "reasoning": {"summary": "auto"},
    }
    if previous_response_id is not None:
        kwargs["previous_response_id"] = previous_response_id
    if compaction_threshold is not None:
        kwargs["extra_body"] = {
            "context_management": [
                {"type": "compaction", "compact_threshold": int(compaction_threshold)}
            ]
        }

    for attempt in range(5):
        try:
            return client.responses.create(**kwargs)
        except Exception as exc:
            print(f"Error calling GPT computer use (attempt {attempt + 1}/5): {exc}")
            time.sleep(2 ** (attempt + 1))

    raise RuntimeError("Failed to get response from GPT computer use after 5 attempts")
