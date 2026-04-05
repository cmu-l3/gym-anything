from __future__ import annotations

import json
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


def call_llm(messages, model, temperature, top_p, top_k=-1, max_tokens=4096, repetition_penalty=1.0):
    for attempt in range(10):
        try:
            print("model: ", model)
            client = openai.OpenAI(
                base_url=os.environ.get("VLM_BASE_URL", "http://localhost:8080/v1"),
                api_key="EMPTY",
            )
            response = client.chat.completions.create(
                model=model,
                messages=messages,
                temperature=temperature,
                top_p=top_p,
                extra_body={"repetition_penalty": repetition_penalty, "top_k": top_k},
                max_tokens=max_tokens,
            )
            print("Raw response from llm: ", response)

            if model in {"Qwen/Qwen3.5-397B-A17B", "Qwen/Qwen3.5-122B-A10B"}:
                reasoning_content = getattr(response.choices[0].message, "reasoning", None)
                if reasoning_content:
                    return f"<think>{reasoning_content}</think>\n{response.choices[0].message.content}"
            return response.choices[0].message.content
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
    tool_version = "20250124"
    beta_flag = "computer-use-2025-01-24"
    tools = [
        {
            "type": f"computer_{tool_version}",
            "name": "computer",
            "display_width_px": 1920,
            "display_height_px": 1080,
        },
        {"type": f"bash_{tool_version}", "name": "bash"},
    ][: 1 if not use_all_tools else None]

    kwargs = {"thinking": {"type": "enabled", "budget_tokens": thinking_budget}} if thinking_budget != -1 else {}
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


def convert_point_format_claude(x, y):
    return int(x * 1920 / 1280), int(y * 1080 / 720)


def claude_parse_tool_result(action_json):
    if "command" in action_json:
        return [{"action": "bash", "command": action_json["command"]}]
    if action_json["action"] == "screenshot":
        return [{"action": "screenshot"}]

    if action_json["action"] == "key":
        actions = [{"keyboard": {"keys": action_json["text"]}}]
    elif action_json["action"] == "type":
        actions = []
        if action_json.get("clear"):
            actions.append({"keyboard": {"keys": ["ctrl", "a"]}})
        actions.append({"keyboard": {"text": action_json["text"]}})
        if action_json.get("enter"):
            actions.append({"keyboard": {"keys": ["Return"]}})
    elif action_json["action"] == "mouse_move":
        x, y = convert_point_format_claude(action_json["coordinate"][0], action_json["coordinate"][1])
        actions = [{"mouse": {"move": [x, y]}}]
    elif action_json["action"] in {"left_click", "click"}:
        x, y = convert_point_format_claude(action_json["coordinate"][0], action_json["coordinate"][1])
        actions = [{"mouse": {"left_click": [x, y]}}]
    elif action_json["action"] == "right_click":
        x, y = convert_point_format_claude(action_json["coordinate"][0], action_json["coordinate"][1])
        actions = [{"mouse": {"right_click": [x, y]}}]
    elif action_json["action"] == "double_click":
        x, y = convert_point_format_claude(action_json["coordinate"][0], action_json["coordinate"][1])
        actions = [{"mouse": {"double_click": [x, y]}}]
    elif action_json["action"] in {"left_click_drag", "drag"}:
        if "start_coordinate" in action_json:
            x1, y1 = convert_point_format_claude(action_json["start_coordinate"][0], action_json["start_coordinate"][1])
            if "end_coordinate" in action_json:
                x2, y2 = convert_point_format_claude(action_json["end_coordinate"][0], action_json["end_coordinate"][1])
            else:
                x2, y2 = convert_point_format_claude(action_json["coordinate"][0], action_json["coordinate"][1])
        else:
            x1, y1 = convert_point_format_claude(action_json["coordinate"][0], action_json["coordinate"][1])
            x2, y2 = convert_point_format_claude(action_json["coordinate2"][0], action_json["coordinate2"][1])
        actions = [
            {"mouse": {"move": [x1, y1]}},
            {"mouse": {"buttons": {"left_down": True}}},
            {"mouse": {"move": [x2, y2]}},
            {"mouse": {"buttons": {"left_up": True}}},
        ]
    elif action_json["action"] == "scroll":
        if "coordinate" in action_json:
            x, y = convert_point_format_claude(action_json["coordinate"][0], action_json["coordinate"][1])
            actions = [
                {"mouse": {"move": [x, y]}},
                {"mouse": {"scroll": action_json["pixels"] if "pixels" in action_json else action_json.get("scroll", 0)}},
            ]
        else:
            actions = [{"mouse": {"scroll": action_json["pixels"] if "pixels" in action_json else action_json.get("scroll", 0)}}]
    elif action_json["action"] == "wait":
        actions = [{"wait": {"time": action_json.get("time", 1.0)}}]
    elif action_json["action"] == "terminate":
        actions = [{"terminate": {"status": action_json.get("status", "success")}}]
    else:
        actions = []

    return actions


def smart_resize(height, width, factor=32, max_pixels=16 * 16 * 4 * 1280):
    del factor, max_pixels
    return height, width
