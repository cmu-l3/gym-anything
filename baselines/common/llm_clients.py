import openai
from baselines.common.prompts import SYSTEM_PROMPT, USER_PROMPT, CLAUDE_SYSTEM_PROMPT
from io import BytesIO
import base64
import json
from anthropic import Anthropic
import uuid
import pickle
import os
from datetime import datetime
import time
import math
import numpy as np
from dotenv import load_dotenv
import litellm
from openai import OpenAI
load_dotenv()

LOG_DUMPS = 'log_dumps_claude'

def get_prompt(instruction, history):
    system_message = SYSTEM_PROMPT
    user_prompt = USER_PROMPT

    messages=[
        {
            "role": "system",
            "content": [
                {"type": "text", "text": "You are a helpful assistant."},
                {"type": "text", "text": system_message}
            ],
        },
        {
            "role": "user",
            "content": [
                {"type": "text", "text": user_prompt.format(instruction=instruction, history=history)}
            ]
        }
    ]
    return messages

def pil_to_base64(image):
    buffered = BytesIO()
    image.save(buffered, format="PNG")
    img_str = base64.b64encode(buffered.getvalue()).decode("utf-8")
    return img_str

def call_kimi_azure(messages, model, temperature, top_p, top_k = -1, max_tokens=4096, repetition_penalty=1.0, return_full_response=False, max_attempts=10):
    
    endpoint = "https://claudefoundary.services.ai.azure.com/openai/v1/"
    model_name = "Kimi-K2.5"
    deployment_name = "Kimi-K2.5"

    api_key = os.getenv("KIMI_API_KEY")

    client = OpenAI(
        base_url=f"{endpoint}",
        api_key=api_key
    )

    for attempt in range(max_attempts):
        try:
            response = client.chat.completions.create(
                model=model,
                messages=messages,
                temperature=temperature,
                top_p=top_p,
            )
            try:
                os.makedirs('model_usage_dumps', exist_ok=True)
                with open(f'model_usage_dumps/{uuid.uuid4()}_{model}.pkl', 'wb') as f:
                    pickle.dump(response.usage, f)
            except Exception as e:
                print(f"Error dumping response: {e}")
            if return_full_response:
                return response
            try:
                reasoning_content = response.choices[0].message.reasoning_content
            except Exception as e:
                print(f"Error getting reasoning content: {e}")
                reasoning_content = None
            if reasoning_content is not None:
                return '<think>' + reasoning_content + '</think>\n' + response.choices[0].message.content
            return response.choices[0].message.content
        except Exception as e:
            print(f"Error calling kimi azure (attempt {attempt+1}/10): {e}")
            time.sleep(2** (attempt+1))
    raise RuntimeError("Failed to get response from Kimi Azure after 10 attempts")

def call_llm(messages, model, temperature, top_p, top_k = -1, max_tokens=4096, repetition_penalty=1.0):
    for attempt in range(10):
        try:
            # if np.random.random() < 0.5:
            # if ('Qwen' in model and 'Qwen3-VL-2B-Thinking' not in model and '4B' in model) or 'qwen3vl-gimp-fix-v3-diff-05-to-60_2s' in model:
            #     client = openai.OpenAI(base_url="http://localhost:4243/v1", api_key="EMPTY")
            # else:
            print('model: ', model)
            vlm_base_url = os.environ.get("VLM_BASE_URL", "http://localhost:8080/v1")
            client = openai.OpenAI(base_url=vlm_base_url, api_key="EMPTY")
            
            response = client.chat.completions.create(
                model=model,
                messages=messages,
                temperature=temperature,    
                top_p=top_p,
                extra_body={"repetition_penalty": repetition_penalty, "top_k": top_k},
                max_tokens=max_tokens,
            )
            print('Raw response from llm: ', response)
            if model == 'Qwen/Qwen3.5-397B-A17B' or model == 'Qwen/Qwen3.5-122B-A10B':
                reasoning_content = response.choices[0].message.reasoning
                if reasoning_content is not None:
                    try:
                        return '<think>' + reasoning_content + '</think>\n' + response.choices[0].message.content
                    except Exception as e:
                        print(f"Error getting reasoning content: {e}")
                        reasoning_content = None
                else:
                    return response.choices[0].message.content
            return response.choices[0].message.content
        except Exception as e:
            print(f"Error calling llm (attempt {attempt+1}/5): {e}")
            time.sleep(2** (attempt+1))
    raise RuntimeError("Failed to get response from LLM after 5 attempts")

def call_gemini_with_search(messages, model="gemini-3-flash-preview", temperature=0.1, max_tokens=16384, timeout=120):
    """Call Gemini with Google Search grounding enabled.
    Model internally decides when to search the web and returns grounded responses."""
    for attempt in range(5):
        try:
            response = litellm.completion(
                model='gemini/' + model,
                messages=messages,
                temperature=temperature,
                max_tokens=max_tokens,
                timeout=timeout,
                tools=[{"google_search": {}},
                       {"code_execution": {}}],
            )
            try:
                os.makedirs('model_usage_dumps', exist_ok=True)
                with open(f'model_usage_dumps/{uuid.uuid4()}_{model}_search.pkl', 'wb') as f:
                    pickle.dump(response.usage, f)
            except Exception:
                pass
            content = response.choices[0].message.content
            if content and content.strip():
                return content
            print(f"Empty response from search call, retrying (attempt {attempt+1})")
        except Exception as e:
            print(f"Search call failed (attempt {attempt+1}/5): {e}")
            time.sleep(2 ** (attempt + 1))
    return None

def call_gemini_with_retry_lowreasoning(messages, model, temperature, top_p, top_k = -1, max_tokens=16384, reasoning_effort='low', timeout=600, return_full_response=False):
    return call_gemini_with_retry(messages, model, temperature, top_p, top_k, max_tokens, reasoning_effort='low', timeout=timeout, return_full_response=return_full_response)

def call_gemini_with_retry(messages, model, temperature, top_p, top_k = -1, max_tokens=16384, reasoning_effort='high', timeout=600, return_full_response=False):
    for attempt in range(5):
        try:
            response = litellm.completion(
                model='gemini/'+model,
                messages=messages,
                temperature=temperature,
                top_p=top_p,
                max_tokens=max_tokens,
                reasoning_effort=reasoning_effort,
                timeout=timeout,
            )
            try:
                os.makedirs('model_usage_dumps', exist_ok=True)
                with open(f'model_usage_dumps/{uuid.uuid4()}_{model}.pkl', 'wb') as f:
                    pickle.dump(response.usage, f)
            except Exception as e:
                print(f"Error dumping response: {e}")
            # print('Raw response from gemini qwen3 style: ', response)
            if return_full_response:
                return response
            try:
                reasoning_content = response.choices[0].message.reasoning_content
            except Exception as e:
                print(f"Error getting reasoning content: {e}")
                reasoning_content = None
            try:
                response.choices[0].message.content
                assert response.choices[0].message.content.strip() != ''
            except Exception as e:
                print('All tokens taken by reasoning, retrying again')
                continue
            if reasoning_content is not None:
                
                return '<think>' + reasoning_content + '</think>\n' + response.choices[0].message.content if not return_full_response else response

            return response.choices[0].message.content
        except Exception as e:
            print(f"Error calling gemini (attempt {attempt+1}/5): {e}")
            time.sleep(2** (attempt+1))
        
    raise RuntimeError("Failed to get response from Gemini after 5 attempts")

def call_gemini(messages, model, temperature, top_p, top_k = -1, max_tokens=16384, reasoning_effort='high', return_full_response=False):
    # breakpoint()

    try:
        response = litellm.completion(
            model='gemini/'+model,
            messages=messages,
            temperature=temperature,
            top_p=top_p,
            max_tokens=max_tokens,
            reasoning_effort=reasoning_effort,
            timeout=600,
        )
    except Exception as e:
        # breakpoint()
        print('error calling gemini: ', e)

    # Dump the response to gemini_qwen3_dumps folder with random uuid
    try:
        os.makedirs('gemini_qwen3_usage_dumps', exist_ok=True)
        with open(f'gemini_qwen3_usage_dumps/{uuid.uuid4()}_{model}.pkl', 'wb') as f:
            pickle.dump(response.usage, f)
    except Exception as e:
        print(f"Error dumping response: {e}")
    # print('Raw response from gemini qwen3 style: ', response)
    try:
        reasoning_content = response.choices[0].message.reasoning_content
    except Exception as e:
        print(f"Error getting reasoning content: {e}")
        reasoning_content = None
    if reasoning_content is not None:
        try:
            if return_full_response:
                return response
            return '<think>' + reasoning_content + '</think>\n' + response.choices[0].message.content
        except Exception as e:
            print(f"Error getting content: {e}", response)
            # breakpoint()
            return 'empty' if not return_full_response else response
    if return_full_response:
        return response
    return response.choices[0].message.content

def call_claude_databricks(messages, model, temperature, top_p, top_k = -1, max_tokens=4096, quit_on_error=False, thinking_budget=2048):
    client = openai.OpenAI(
        base_url=os.environ.get("DATABRICKS_BASE_URL", "https://YOUR_DATABRICKS_WORKSPACE.azuredatabricks.net/serving-endpoints"),
        api_key=os.environ.get("DATABRICKS_API_KEY", ""),
    )

    response = None
    for attempt in range(5):
        try:
            response = client.chat.completions.create(
                model=model,
                messages=messages,
                # temperature=temperature,
                # top_p=top_p,
                # extra_body={"repetition_penalty": 1.0, "top_k": top_k},
                max_tokens=max_tokens,
                extra_headers={"anthropic-beta": "beta_flag"},
                extra_body={
                    "thinking": {
                        "type": "enabled",
                        "budget_tokens": thinking_budget
                    }
                }
            )
            break
        except Exception as e:
            print(f"Error calling claude (attempt {attempt+1}/5): {e}")
            # breakpoint()
            time.sleep(2** (attempt+1))
            if quit_on_error:
                raise e
    
    if response is None:
        raise RuntimeError("Failed to get response from Claude after 5 attempts")
    
    print(response.usage)
    # dump the usage to claude_usage_dumps folder with random uuid
    try:
        os.makedirs('model_usage_dumps', exist_ok=True)
        with open(f'model_usage_dumps/{uuid.uuid4()}_{model}.pkl', 'wb') as f:
            pickle.dump(response.usage, f)
    except Exception as e:
        print(f"Error dumping usage: {e}")
    print(response.choices[0].message.content)
    
    # Parse response content robustly - handle different response formats
    content = response.choices[0].message.content
    
    # Handle case where content is a string (not a list)
    if isinstance(content, str):
        return content
    
    # Handle case where content is a list
    if isinstance(content, list):
        think_text = ""
        response_text = ""
        
        for item in content:
            if isinstance(item, dict):
                # Handle 'reasoning' or 'summary' type (thinking block)
                if item.get('type') == 'reasoning' and 'summary' in item:
                    summary = item['summary']
                    if isinstance(summary, list) and len(summary) > 0:
                        if isinstance(summary[0], dict) and 'text' in summary[0]:
                            think_text = summary[0]['text']
                        elif isinstance(summary[0], str):
                            think_text = summary[0]
                # Handle 'text' type (response block)
                elif item.get('type') == 'text' and 'text' in item:
                    response_text = item['text']
                # Handle direct 'text' key
                elif 'text' in item:
                    response_text = item['text']
                # Handle 'summary' key directly
                elif 'summary' in item:
                    summary = item['summary']
                    if isinstance(summary, list) and len(summary) > 0:
                        if isinstance(summary[0], dict) and 'text' in summary[0]:
                            think_text = summary[0]['text']
            elif isinstance(item, str):
                response_text += item
        
        # If we got both thinking and response, combine them
        if think_text and response_text:
            return '<think>' + think_text + '</think>' + response_text
        elif response_text:
            return response_text
        elif think_text:
            return '<think>' + think_text + '</think>'
        
        # Fallback: try the original format
        try:
            return '<think>' + content[0]['summary'][0]['text'] + '</think>' + content[1]['text']
        except (IndexError, KeyError, TypeError):
            # Last resort: convert entire content to string
            return str(content)
    
    # Fallback for unexpected types
    return str(content)

def call_claude_databricks_litellm(messages, model, temperature, top_p, top_k = -1, max_tokens=4096):
    client = openai.OpenAI(
        base_url=os.environ.get("DATABRICKS_BASE_URL", "https://YOUR_DATABRICKS_WORKSPACE.azuredatabricks.net/serving-endpoints"),
        api_key=os.environ.get("DATABRICKS_API_KEY", ""),
    )
    response = client.chat.completions.create(
        model=model,
        messages=messages,
        # temperature=temperature,
        # top_p=top_p,
        # extra_body={"repetition_penalty": 1.0, "top_k": top_k},
        max_tokens=max_tokens,
    )
    return response.choices[0].message.content


def call_claude_with_retry(client, model, max_tokens, messages, system_prompt, tools, beta_flag, temperature, retries = 5, **kwargs):

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
                # top_p=top_p,
                **kwargs,
            )
            print(response.usage)
            break
        except Exception as e:
            print(f"Error calling claude: {e}")
            time.sleep(2** (attempt+1))
    return response
                           

def call_claude(messages, model, temperature, top_p, thinking_budget = 8192, system_prompt = CLAUDE_SYSTEM_PROMPT, use_all_tools = False, use_no_tools = False):
    client = Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))

    tool_version = "20250124"
    beta_flag = "computer-use-2025-01-24" if "20250124" in tool_version else "computer-use-2024-10-22"
    tool_version_text = '20250728' if '4-5' in model else tool_version
    tools = [
        {"type": f"computer_{tool_version}", "name": "computer", "display_width_px": 1920, "display_height_px": 1080},
        # {"type": f"text_editor_{tool_version_text}", "name": "str_replace_based_edit_tool" if '20250728' in tool_version_text else "str_replace_editor"},
        {"type": f"bash_{tool_version}", "name": "bash"}
    ][:1 if not use_all_tools else None]

    thinking = {"type": "enabled", "budget_tokens": thinking_budget}

    if thinking_budget!=-1:
        kwargs = {'thinking': thinking}
    else:
        kwargs = {}

    response = call_claude_with_retry(client, model, 16384, messages, system_prompt, tools if not use_no_tools else [], beta_flag, temperature, **kwargs)
    # breakpoint()
    

    try:
        os.makedirs(LOG_DUMPS, exist_ok=True)
        with open(f'{LOG_DUMPS}/{uuid.uuid4()}.pkl', 'wb') as f:
            pickle.dump(response, f)
    except Exception as e:
        print(f"Error dumping response: {e}")

    return response

def convert_point_format(x, y):
    x_ = x * 1920 / 1932
    y_ = y * 1080 / 1092
    return int(x_), int(y_)

def convert_point_format_qwen3vl(x, y, scale_dims = True, scale_dims_ratio = (1920/1000, 1080/1000)):
    if scale_dims:
        x_ = x * scale_dims_ratio[0]
        y_ = y * scale_dims_ratio[1]
    else:
        x_ = x
        y_ = y

    return int(x_), int(y_)

def parse_qwen3vl_response(response, scale_dims = True, scale_dims_ratio = (1920/1000, 1080/1000)):
    # Handle empty or None response
    if not response or not isinstance(response, str):
        return {
            'actions': [{'action': 'screenshot'}],
            'metadata': {
                'thought': 'Empty or invalid response',
                'conclusion': 'Retrying with screenshot',
                'action_type': 'screenshot',
                'is_terminal': False,
                'wait_time': None,
                'parse_error': True
            }
        }
    
    thought = response.split("</think>")[0]
    conclusion = None
    if '</think>' in response:
        response = response.split("</think>")[1]
    print(f"[parse_qwen3vl_response] Just a test")
    # Check if response looks garbled (contains control characters or is mostly non-ASCII)
    printable_ratio = sum(1 for c in response if c.isprintable() or c.isspace()) / max(len(response), 1)
    if printable_ratio < 0.5:
        print(f"[parse_qwen3vl_response] Warning: Response appears garbled (printable ratio: {printable_ratio:.2f})")
        return {
            'actions': [{'action': 'screenshot'}],
            'metadata': {
                'thought': 'Garbled response detected',
                'conclusion': 'Retrying with screenshot',
                'action_type': 'screenshot',
                'is_terminal': False,
                'wait_time': None,
                'parse_error': True
            }
        }
    
    if "<tool_call>" in response and "</tool_call>" in response:
        action = response.split("<tool_call>")[-1].split("</tool_call>")[0]
    else:
        try:
            action = '{"name": "computer_use"' + response.split('{"name": "computer_use"')[1].split("}}")[0] + '}}'
        except Exception as e:
            # We assume that the task is complete.
            print(f"[parse_qwen3vl_response] Error parsing action, switching to wait: {e}", response)
            # action = '{"action": "terminate", "status": "success"}'
            action = '{"action": "wait", "time": 1.0}'
            conclusion = "cannot parse action. waiting for 1 second and trying again"
    
    for line in response.split("\n"):
        if 'Action:' in line:
            conclusion = line.split("Action:")[-1].strip()
    if conclusion is None:
        conclusion = response.split("<tool_call>")[0].strip()
    
    # Parse action JSON with robust error handling
    try:
        parsed_action = json.loads(action.strip('\n'))
        # Handle both direct action format and nested arguments format
        if 'arguments' in parsed_action:
            action_json = parsed_action['arguments']
        elif 'action' in parsed_action:
            action_json = parsed_action
        else:
            raise ValueError("No 'arguments' or 'action' key in parsed JSON")
    except (json.JSONDecodeError, ValueError, KeyError) as e:
        print(f"[parse_qwen3vl_response] Error parsing action JSON: {e}", action)
        return {
            'actions': [{'action': 'screenshot'}],
            'metadata': {
                'thought': thought,
                'conclusion': f'Parse error: {e}',
                'action_type': 'screenshot',
                'is_terminal': False,
                'wait_time': None,
                'parse_error': True
            }
        }
    
    # Ensure action_json has required 'action' key
    if 'action' not in action_json:
        print(f"[parse_qwen3vl_response] Missing 'action' key in: {action_json}")
        return {
            'actions': [{'action': 'screenshot'}],
            'metadata': {
                'thought': thought,
                'conclusion': 'Missing action key',
                'action_type': 'screenshot',
                'is_terminal': False,
                'wait_time': None,
                'parse_error': True
            }
        }

    metadata = {
        'thought': thought,
        'conclusion': conclusion,
        'action_type': action_json['action'],
        'is_terminal': False,
        'wait_time': None
    }

    if action_json['action'] == 'key':
        actions = [{'keyboard': {'keys': action_json['keys']}}]
    elif action_json['action'] == 'type':
        actions = []
        if 'clear' in action_json and action_json['clear']:
            actions.append({'keyboard': {'keys': ['ctrl', 'a']}})
        actions.append({'keyboard': {'text': action_json['text']}})
        if 'enter' in action_json and action_json['enter']:
            actions.append({'keyboard': {'keys': ['Return']}})
    elif action_json['action'] == 'mouse_move':
        x, y = convert_point_format_qwen3vl(action_json['coordinate'][0], action_json['coordinate'][1], scale_dims, scale_dims_ratio)
        actions = [{'mouse': {'move': [x, y]}}]
    elif action_json['action'] in ['left_click', 'click']:
        x, y = convert_point_format_qwen3vl(action_json['coordinate'][0], action_json['coordinate'][1], scale_dims, scale_dims_ratio)
        actions = [{'mouse': {'left_click': [x, y]}}]
    elif action_json['action'] == 'right_click':
        x, y = convert_point_format_qwen3vl(action_json['coordinate'][0], action_json['coordinate'][1], scale_dims, scale_dims_ratio)
        actions = [{'mouse': {'right_click': [x, y]}}]
    elif action_json['action'] == 'double_click':
        x, y = convert_point_format_qwen3vl(action_json['coordinate'][0], action_json['coordinate'][1], scale_dims, scale_dims_ratio)
        actions = [{'mouse': {'double_click': [x, y]}}]
    elif action_json['action'] == 'triple_click':
        x, y = convert_point_format_qwen3vl(action_json['coordinate'][0], action_json['coordinate'][1], scale_dims, scale_dims_ratio)
        actions = [{'mouse': {'triple_click': [x, y]}}]
    elif action_json['action'] in ['left_click_drag', 'drag']:
        x1, y1 = convert_point_format_qwen3vl(action_json['coordinate'][0], action_json['coordinate'][1], scale_dims, scale_dims_ratio)
        try:
            x2, y2 = convert_point_format_qwen3vl(action_json['coordinate2'][0], action_json['coordinate2'][1], scale_dims, scale_dims_ratio)
        except Exception as e:
            print(f"[parse_qwen3vl_response] Error parsing coordinate2: {e}")
            print('Action json: ', action_json)
            x2, y2 = x1, y1
        actions = [{'mouse': {'left_click_drag': [[x1, y1], [x2, y2]]}}]
        # actions = [
        #     {'mouse': {'move': [x1, y1]}},
        #     {'mouse': {'buttons': {'left_down': True}}},
        #     {'mouse': {'move': [x2, y2]}},
        #     {'mouse': {'buttons': {'left_up': True}}}
        # ]
    elif action_json['action'] == 'scroll':
        # Check if coordinate is provided for scroll position
        if 'coordinate' in action_json:
            x, y = convert_point_format_qwen3vl(action_json['coordinate'][0], action_json['coordinate'][1], scale_dims, scale_dims_ratio)
            actions = [
                {'mouse': {'move': [x, y]}},
                {'mouse': {'scroll': action_json['pixels'] if 'pixels' in action_json else action_json.get('scroll', 0)}}
            ]
        else:
            actions = [{'mouse': {'scroll': action_json['pixels'] if 'pixels' in action_json else action_json.get('scroll', 0)}}]
    elif action_json['action'] == 'wait':
        # Wait actions don't have direct gym equivalent - signal to caller to wait
        actions = []
        metadata['wait_time'] = action_json.get('time', 1.0)  # Default to 1 second
    elif action_json['action'] == 'terminate':
        # Terminate actions signal completion
        actions = []
        metadata['is_terminal'] = True
        metadata['status'] = action_json.get('status', 'success')  # success or fail
    else:
        # Unknown action - return empty actions
        actions = []
        

    return {'actions': actions, 'metadata': metadata}


def parse_qwen3vl_memory_response(response, scale_dims=True, scale_dims_ratio=(1920/1000, 1080/1000)):
    """
    Parse Qwen3VL Memory agent response with Memory/Progress/Intention/Action format.

    Expected response format:
        Memory: {"key": "value", ...}
        Progress: {"subtask1": "finished", ...}
        Intention: "current subtask"
        Action: description
        <tool_call>{"name": "computer_use", "arguments": {...}}</tool_call>

    Returns:
        Dict with 'actions', 'metadata', 'memory', 'progress', 'intention' keys
    """
    import re

    # Handle empty or None response
    if not response or not isinstance(response, str):
        return {
            'actions': [{'action': 'screenshot'}],
            'metadata': {
                'thought': 'Empty or invalid response',
                'conclusion': 'Retrying with screenshot',
                'action_type': 'screenshot',
                'is_terminal': False,
                'wait_time': None,
                'parse_error': True
            },
            'memory': {},
            'progress': {},
            'intention': ''
        }

    # Handle thinking tags if present
    thought = ""
    working_response = response
    if '</think>' in response:
        thought = response.split("</think>")[0]
        working_response = response.split("</think>")[1]

    # Check if response looks garbled
    printable_ratio = sum(1 for c in working_response if c.isprintable() or c.isspace()) / max(len(working_response), 1)
    if printable_ratio < 0.5:
        print(f"[parse_qwen3vl_memory_response] Warning: Response appears garbled (printable ratio: {printable_ratio:.2f})")
        return {
            'actions': [{'action': 'screenshot'}],
            'metadata': {
                'thought': 'Garbled response detected',
                'conclusion': 'Retrying with screenshot',
                'action_type': 'screenshot',
                'is_terminal': False,
                'wait_time': None,
                'parse_error': True
            },
            'memory': {},
            'progress': {},
            'intention': ''
        }

    # Extract Memory (JSON format)
    memory = {}
    memory_match = re.search(r'Memory:\s*(\{[^}]*\})', working_response, re.DOTALL)
    if memory_match:
        try:
            memory = json.loads(memory_match.group(1))
        except json.JSONDecodeError as e:
            print(f"[parse_qwen3vl_memory_response] Failed to parse Memory JSON: {e}")

    # Extract Progress (JSON format)
    progress = {}
    progress_match = re.search(r'Progress:\s*(\{[^}]*\})', working_response, re.DOTALL)
    if progress_match:
        try:
            progress = json.loads(progress_match.group(1))
        except json.JSONDecodeError as e:
            print(f"[parse_qwen3vl_memory_response] Failed to parse Progress JSON: {e}")

    # Extract Intention (string after "Intention:")
    intention = ""
    intention_match = re.search(r'Intention:\s*["\']?([^"\'\n]+)["\']?', working_response)
    if intention_match:
        intention = intention_match.group(1).strip().strip('"\'')

    # Extract Action description
    conclusion = ""
    action_match = re.search(r'Action:\s*(.+?)(?=<tool_call>|$)', working_response, re.DOTALL)
    if action_match:
        conclusion = action_match.group(1).strip()

    # Extract tool_call
    action_json = None
    if "<tool_call>" in working_response and "</tool_call>" in working_response:
        action_str = working_response.split("<tool_call>")[-1].split("</tool_call>")[0]
        try:
            parsed_action = json.loads(action_str.strip('\n'))
            if 'arguments' in parsed_action:
                action_json = parsed_action['arguments']
            elif 'action' in parsed_action:
                action_json = parsed_action
            else:
                raise ValueError("No 'arguments' or 'action' key in parsed JSON")
        except (json.JSONDecodeError, ValueError) as e:
            print(f"[parse_qwen3vl_memory_response] Error parsing tool_call JSON: {e}")
    else:
        # Try fallback parsing
        try:
            action_str = '{"name": "computer_use"' + working_response.split('{"name": "computer_use"')[1].split("}}")[0] + '}}'
            parsed_action = json.loads(action_str.strip('\n'))
            action_json = parsed_action.get('arguments', parsed_action)
        except Exception as e:
            print(f"[parse_qwen3vl_memory_response] Fallback parsing failed: {e}")
            # Assume task completion
            action_json = {'action': 'terminate', 'status': 'success'}

    # Handle case where action_json is still None
    if action_json is None:
        return {
            'actions': [{'action': 'screenshot'}],
            'metadata': {
                'thought': thought,
                'conclusion': conclusion or 'Parse error',
                'action_type': 'screenshot',
                'is_terminal': False,
                'wait_time': None,
                'parse_error': True
            },
            'memory': memory,
            'progress': progress,
            'intention': intention
        }

    # Ensure action_json has required 'action' key
    if 'action' not in action_json:
        print(f"[parse_qwen3vl_memory_response] Missing 'action' key in: {action_json}")
        return {
            'actions': [{'action': 'screenshot'}],
            'metadata': {
                'thought': thought,
                'conclusion': 'Missing action key',
                'action_type': 'screenshot',
                'is_terminal': False,
                'wait_time': None,
                'parse_error': True
            },
            'memory': memory,
            'progress': progress,
            'intention': intention
        }

    # Build metadata
    metadata = {
        'thought': thought,
        'conclusion': conclusion or intention,
        'action_type': action_json['action'],
        'is_terminal': False,
        'wait_time': None
    }

    # Convert action to gym format (same logic as parse_qwen3vl_response)
    if action_json['action'] == 'key':
        actions = [{'keyboard': {'keys': action_json['keys']}}]
    elif action_json['action'] == 'type':
        actions = []
        if 'clear' in action_json and action_json['clear']:
            actions.append({'keyboard': {'keys': ['ctrl', 'a']}})
        actions.append({'keyboard': {'text': action_json['text']}})
        if 'enter' in action_json and action_json['enter']:
            actions.append({'keyboard': {'keys': ['Return']}})
    elif action_json['action'] == 'mouse_move':
        x, y = convert_point_format_qwen3vl(action_json['coordinate'][0], action_json['coordinate'][1], scale_dims, scale_dims_ratio)
        actions = [{'mouse': {'move': [x, y]}}]
    elif action_json['action'] in ['left_click', 'click']:
        x, y = convert_point_format_qwen3vl(action_json['coordinate'][0], action_json['coordinate'][1], scale_dims, scale_dims_ratio)
        actions = [{'mouse': {'left_click': [x, y]}}]
    elif action_json['action'] == 'right_click':
        x, y = convert_point_format_qwen3vl(action_json['coordinate'][0], action_json['coordinate'][1], scale_dims, scale_dims_ratio)
        actions = [{'mouse': {'right_click': [x, y]}}]
    elif action_json['action'] == 'double_click':
        x, y = convert_point_format_qwen3vl(action_json['coordinate'][0], action_json['coordinate'][1], scale_dims, scale_dims_ratio)
        actions = [{'mouse': {'double_click': [x, y]}}]
    elif action_json['action'] == 'triple_click':
        x, y = convert_point_format_qwen3vl(action_json['coordinate'][0], action_json['coordinate'][1], scale_dims, scale_dims_ratio)
        actions = [{'mouse': {'triple_click': [x, y]}}]
    elif action_json['action'] in ['left_click_drag', 'drag']:
        x1, y1 = convert_point_format_qwen3vl(action_json['coordinate'][0], action_json['coordinate'][1], scale_dims, scale_dims_ratio)
        try:
            x2, y2 = convert_point_format_qwen3vl(action_json['coordinate2'][0], action_json['coordinate2'][1], scale_dims, scale_dims_ratio)
        except Exception as e:
            print(f"[parse_qwen3vl_memory_response] Error parsing coordinate2: {e}")
            x2, y2 = x1, y1
        actions = [{'mouse': {'left_click_drag': [[x1, y1], [x2, y2]]}}]
    elif action_json['action'] == 'scroll':
        if 'coordinate' in action_json:
            x, y = convert_point_format_qwen3vl(action_json['coordinate'][0], action_json['coordinate'][1], scale_dims, scale_dims_ratio)
            actions = [
                {'mouse': {'move': [x, y]}},
                {'mouse': {'scroll': action_json['pixels'] if 'pixels' in action_json else action_json.get('scroll', 0)}}
            ]
        else:
            actions = [{'mouse': {'scroll': action_json['pixels'] if 'pixels' in action_json else action_json.get('scroll', 0)}}]
    elif action_json['action'] == 'wait':
        actions = []
        metadata['wait_time'] = action_json.get('time', 1.0)
    elif action_json['action'] == 'terminate':
        actions = []
        metadata['is_terminal'] = True
        metadata['status'] = action_json.get('status', 'success')
    else:
        actions = []

    return {
        'actions': actions,
        'metadata': metadata,
        'memory': memory,
        'progress': progress,
        'intention': intention
    }


def parse_owl_response(response):
    thought = ""
    if "<thinking>" in response and "</thinking>" in response:
        thought = response.split("<thinking>")[-1].split("</thinking>")[0]
    elif "<thinking>" in response:
        thought = response.split("<thinking>")[1]
    
    conclusion = ""
    if "<conclusion>" in response and "</conclusion>" in response:
        conclusion = response.split("<conclusion>")[-1].split("</conclusion>")[0]
    elif "<conclusion>" in response:
        conclusion = response.split("<conclusion>")[1]
    if conclusion == "" and thought != "":
        conclusion = thought

    if "<tool_call>" in response and "</tool_call>" in response:
        action = response.split("<tool_call>")[-1].split("</tool_call>")[0]
    else:
        action = '{"name": "computer_use"' + response.split('{"name": "computer_use"')[1].split("}}")[0] + '}}'
        
    action_json = json.loads(action.strip('\n'))['arguments']
    
    # Initialize metadata for special actions
    metadata = {
        'thought': thought,
        'conclusion': conclusion,
        'action_type': action_json['action'],
        'is_terminal': False,
        'wait_time': None
    }

    if action_json['action'] == 'key':
        actions = [{'keyboard': {'keys': action_json['keys']}}]
    elif action_json['action'] == 'type':
        actions = []
        if 'clear' in action_json and action_json['clear']:
            actions.append({'keyboard': {'keys': ['ctrl', 'a']}})
        actions.append({'keyboard': {'text': action_json['text']}})
        if 'enter' in action_json and action_json['enter']:
            actions.append({'keyboard': {'keys': ['Return']}})
    elif action_json['action'] == 'mouse_move':
        x, y = convert_point_format(action_json['coordinate'][0], action_json['coordinate'][1])
        actions = [{'mouse': {'move': [x, y]}}]
    elif action_json['action'] in ['left_click', 'click']:
        x, y = convert_point_format(action_json['coordinate'][0], action_json['coordinate'][1])
        actions = [{'mouse': {'left_click': [x, y]}}]
        # x, y = convert_point_format(action_json['coordinate'][0], action_json['coordinate'][1])
        # actions = [
        #     {'mouse': {'move': [x, y]}},
        #     {'mouse': {'buttons': {'left_down': True}}},
        #     {'mouse': {'buttons': {'left_up': True}}}
        # ]
    elif action_json['action'] == 'right_click':
        x, y = convert_point_format(action_json['coordinate'][0], action_json['coordinate'][1])
        actions = [{'mouse': {'right_click': [x, y]}}]
        # x, y = convert_point_format(action_json['coordinate'][0], action_json['coordinate'][1])
        # actions = [
        #     {'mouse': {'move': [x, y]}},
        #     {'mouse': {'buttons': {'right_down': True}}}
        # ]
    elif action_json['action'] == 'double_click':
        x, y = convert_point_format(action_json['coordinate'][0], action_json['coordinate'][1])
        actions = [{'mouse': {'double_click': [x, y]}}]
        # x, y = convert_point_format(action_json['coordinate'][0], action_json['coordinate'][1])
        # actions = [
        #     {'mouse': {'move': [x, y]}},
        #     {'mouse': {'buttons': {'left_down': True}}},
        #     {'mouse': {'buttons': {'left_up': True}}},
        #     {'mouse': {'buttons': {'left_down': True}}},
        #     {'mouse': {'buttons': {'left_up': True}}}
        # ]
    elif action_json['action'] in ['left_click_drag', 'drag']:
        x1, y1 = convert_point_format(action_json['coordinate'][0], action_json['coordinate'][1])
        x2, y2 = convert_point_format(action_json['coordinate2'][0], action_json['coordinate2'][1])
        actions = [
            {'mouse': {'move': [x1, y1]}},
            {'mouse': {'buttons': {'left_down': True}}},
            {'mouse': {'move': [x2, y2]}},
            {'mouse': {'buttons': {'left_up': True}}}
        ]
    elif action_json['action'] == 'scroll':
        # Check if coordinate is provided for scroll position
        if 'coordinate' in action_json:
            x, y = convert_point_format(action_json['coordinate'][0], action_json['coordinate'][1])
            actions = [
                {'mouse': {'move': [x, y]}},
                {'mouse': {'scroll': action_json['pixels'] if 'pixels' in action_json else action_json.get('scroll', 0)}}
            ]
        else:
            actions = [{'mouse': {'scroll': action_json['pixels'] if 'pixels' in action_json else action_json.get('scroll', 0)}}]
    elif action_json['action'] == 'wait':
        # Wait actions don't have direct gym equivalent - signal to caller to wait
        actions = []
        metadata['wait_time'] = action_json.get('time', 1.0)  # Default to 1 second
    elif action_json['action'] == 'terminate':
        # Terminate actions signal completion
        actions = []
        metadata['is_terminal'] = True
        metadata['status'] = action_json.get('status', 'success')  # success or fail
    else:
        # Unknown action - return empty actions
        actions = []
        

    return {'actions': actions, 'metadata': metadata}

def convert_point_format_claude(x, y):
    # return int(x)*1.5, int(y)*1.35
    # return int(x*1920/1366), int(y*1080/768)
    # return int(x), int(y)
    return int(x*1920/1280), int(y*1080/720)


def create_zoom_crop(image_path, x, y, crop_size=100):
    """
    Create a zoomed crop of an image around the specified coordinates.
    
    Args:
        image_path: Path to the image file
        x, y: Center coordinates for the crop
        crop_size: Size of the crop (default 100x100)
    
    Returns:
        Base64 encoded cropped image
    """
    from PIL import Image
    import base64
    from io import BytesIO
    
    img = Image.open(image_path)
    width, height = img.size
    
    # Calculate crop boundaries (centered on x, y)
    half_size = crop_size // 2
    left = max(0, x - half_size)
    top = max(0, y - half_size)
    right = min(width, x + half_size)
    bottom = min(height, y + half_size)
    
    # Crop the image
    cropped = img.crop((left, top, right, bottom))
    # breakpoint()
    # Convert to base64
    buffered = BytesIO()
    cropped.save(buffered, format="PNG")
    img_str = base64.b64encode(buffered.getvalue()).decode("utf-8")
    
    return img_str


def claude_parse_tool_result(action_json):


    if 'command' in action_json:
        # breakpoint()
        return [{'action': 'bash', 'command': action_json['command']}]


    if action_json['action'] == 'screenshot':
        return [{'action': 'screenshot'}]



    if action_json['action'] == 'key':
        actions = [{'keyboard': {'keys': action_json['text']}}]
    elif action_json['action'] == 'type':
        actions = []
        if 'clear' in action_json and action_json['clear']:
            actions.append({'keyboard': {'keys': ['ctrl', 'a']}})
        actions.append({'keyboard': {'text': action_json['text']}})
        if 'enter' in action_json and action_json['enter']:
            actions.append({'keyboard': {'keys': ['Return']}})
    elif action_json['action'] == 'mouse_move':
        x, y = convert_point_format_claude(action_json['coordinate'][0], action_json['coordinate'][1])
        actions = [{'mouse': {'move': [x, y]}}]
    elif action_json['action'] in ['left_click', 'click']:
        x, y = convert_point_format_claude(action_json['coordinate'][0], action_json['coordinate'][1])
        actions = [
            {'mouse': {'left_click': [x, y]}}
        ]
        # x, y = convert_point_format_claude(action_json['coordinate'][0], action_json['coordinate'][1])
        # actions = [
        #     {'mouse': {'move': [x, y]}},
        #     {'mouse': {'buttons': {'left_down': True}}},
        #     {'mouse': {'buttons': {'left_up': True}}}
        # ]
    elif action_json['action'] == 'right_click':
        x, y = convert_point_format_claude(action_json['coordinate'][0], action_json['coordinate'][1])
        actions = [
            {'mouse': {'right_click': [x, y]}}
        ]
        # x, y = convert_point_format_claude(action_json['coordinate'][0], action_json['coordinate'][1])
        # actions = [
        #     {'mouse': {'move': [x, y]}},
        #     {'mouse': {'buttons': {'right_down': True}}}
        # ]
    elif action_json['action'] == 'double_click':
        x, y = convert_point_format_claude(action_json['coordinate'][0], action_json['coordinate'][1])
        actions = [
            {'mouse': {'double_click': [x, y]}}
        ]
        # x, y = convert_point_format_claude(action_json['coordinate'][0], action_json['coordinate'][1])
        # actions = [
        #     {'mouse': {'move': [x, y]}},
        #     {'mouse': {'buttons': {'left_down': True}}},
        #     {'mouse': {'buttons': {'left_up': True}}},
        #     {'mouse': {'buttons': {'left_down': True}}},
        #     {'mouse': {'buttons': {'left_up': True}}}
        # ]
    elif action_json['action'] in ['left_click_drag', 'drag']:
        if 'start_coordinate' in action_json:
            x1, y1 = convert_point_format_claude(action_json['start_coordinate'][0], action_json['start_coordinate'][1])
            if 'end_coordinate' in action_json:
                x2, y2 = convert_point_format_claude(action_json['end_coordinate'][0], action_json['end_coordinate'][1])
            else:
                x2, y2 = convert_point_format_claude(action_json['coordinate'][0], action_json['coordinate'][1])
        else:
            x1, y1 = convert_point_format_claude(action_json['coordinate'][0], action_json['coordinate'][1])
            x2, y2 = convert_point_format_claude(action_json['coordinate2'][0], action_json['coordinate2'][1])
        actions = [
            {'mouse': {'move': [x1, y1]}},
            {'mouse': {'buttons': {'left_down': True}}},
            {'mouse': {'move': [x2, y2]}},
            {'mouse': {'buttons': {'left_up': True}}}
        ]
    elif action_json['action'] == 'scroll':
        # Check if coordinate is provided for scroll position
        if 'coordinate' in action_json:
            x, y = convert_point_format_claude(action_json['coordinate'][0], action_json['coordinate'][1])
            actions = [
                {'mouse': {'move': [x, y]}},
                {'mouse': {'scroll': action_json['pixels'] if 'pixels' in action_json else action_json.get('scroll', 0)}}
            ]
        else:
            actions = [{'mouse': {'scroll': action_json['pixels'] if 'pixels' in action_json else action_json.get('scroll', 0)}}]
    elif action_json['action'] == 'wait':
        # Wait actions don't have direct gym equivalent - signal to caller to wait
        actions = [{'wait': {'time': action_json.get('time', 1.0)}}]
    elif action_json['action'] == 'terminate':
        # Terminate actions signal completion
        actions = [{'terminate': {'status': action_json.get('status', 'success')}}]
    else:
        # Unknown action - return empty actions
        actions = []

    return actions


def smart_resize(height, width, factor=32, max_pixels=16 * 16 * 4 * 1280):
    """
    Smart resize function for Qwen VL models.
    Resizes image to be divisible by factor and within max_pixels constraint.
    
    Args:
        height: Original image height
        width: Original image width
        factor: Factor to make dimensions divisible by (default 32)
        max_pixels: Maximum number of pixels (default 16*16*4*1280)
    
    Returns:
        Tuple of (new_height, new_width)
    """
    return height, width
    # Calculate current number of pixels
    current_pixels = height * width
    
    # If already within limit, just round to factor
    if current_pixels <= max_pixels:
        new_height = (height // factor) * factor
        new_width = (width // factor) * factor
        if new_height == 0:
            new_height = factor
        if new_width == 0:
            new_width = factor
        return new_height, new_width
    
    # Need to downscale
    scale = math.sqrt(max_pixels / current_pixels)
    new_height = int(height * scale)
    new_width = int(width * scale)
    
    # Round to factor
    new_height = (new_height // factor) * factor
    new_width = (new_width // factor) * factor
    
    # Ensure non-zero dimensions
    if new_height == 0:
        new_height = factor
    if new_width == 0:
        new_width = factor
    
    return new_height, new_width


def call_qwen_llm(messages, model, temperature, top_p, max_tokens=1500):
    """
    Call Qwen LLM via OpenAI-compatible API.
    
    Args:
        messages: List of message dicts
        model: Model name (e.g., 'qwen3-vl')
        temperature: Temperature for sampling
        top_p: Top-p for sampling
        max_tokens: Maximum tokens to generate
    
    Returns:
        Response string
    """
    base_url = os.getenv("QWEN_BASE_URL", "https://poc-dashscope.aliyuncs.com/compatible-mode/v1")
    api_key = os.getenv("QWEN_API_KEY", "sk-123")
    
    client = openai.OpenAI(base_url=base_url, api_key=api_key)
    
    max_retries = 5
    for attempt in range(max_retries):
        try:
            response = client.chat.completions.create(
                model=model,
                messages=messages,
                max_tokens=max_tokens,
                temperature=temperature,
                top_p=top_p,
            )
            return response.choices[0].message.content
        except Exception as e:
            print(f"Error calling Qwen model (attempt {attempt + 1}/{max_retries}): {e}")
            if attempt < max_retries - 1:
                time.sleep(2 ** attempt)  # Exponential backoff
            else:
                raise
    
    return ""


# UITars-specific helper functions
import re
import ast

def convert_point_to_coordinates_uitars(text, is_answer=False):
    """Convert <point>x y</point> format to (x, y) coordinates."""
    pattern = r"<point>(\d+)\s+(\d+)</point>"
    
    def replace_match(match):
        x1, y1 = map(int, match.groups())
        x = (x1 + x1) // 2
        y = (y1 + y1) // 2
        if is_answer:
            return f"({x},{y})"
        return f"({x},{y})"
    
    text = re.sub(r"\[EOS\]", "", text)
    return re.sub(pattern, replace_match, text).strip()


def parse_action_uitars(action_str):
    """Parse a single action string into function name and arguments."""
    try:
        node = ast.parse(action_str, mode='eval')
        
        if not isinstance(node, ast.Expression):
            raise ValueError("Not an expression")
        
        call = node.body
        
        if not isinstance(call, ast.Call):
            raise ValueError("Not a function call")
        
        if isinstance(call.func, ast.Name):
            func_name = call.func.id
        elif isinstance(call.func, ast.Attribute):
            func_name = call.func.attr
        else:
            func_name = None
        
        kwargs = {}
        for kw in call.keywords:
            key = kw.arg
            if isinstance(kw.value, ast.Constant):
                value = kw.value.value
            elif isinstance(kw.value, ast.Str):
                value = kw.value.s
            else:
                value = None
            kwargs[key] = value
        
        return {
            'function': func_name,
            'args': kwargs
        }
    
    except Exception as e:
        print(f"Failed to parse action '{action_str}': {e}")
        return None


def escape_single_quotes_uitars(text):
    """Escape unescaped single quotes in text."""
    pattern = r"(?<!\\)'"
    return re.sub(pattern, r"\\'", text)


def round_by_factor(number: int, factor: int) -> int:
    """Returns the closest integer to 'number' that is divisible by 'factor'."""
    return round(number / factor) * factor


def ceil_by_factor(number: int, factor: int) -> int:
    """Returns the smallest integer >= 'number' that is divisible by 'factor'."""
    return math.ceil(number / factor) * factor


def floor_by_factor(number: int, factor: int) -> int:
    """Returns the largest integer <= 'number' that is divisible by 'factor'."""
    return math.floor(number / factor) * factor


def linear_resize_uitars(
    height: int, width: int, factor: int = 28, 
    min_pixels: int = 100 * 28 * 28, max_pixels: int = 16384 * 28 * 28
) -> tuple:
    """Linear resize maintaining aspect ratio for UITars."""
    if width * height > max_pixels:
        resize_factor = math.sqrt(max_pixels / (width * height))
        width, height = int(width * resize_factor), int(height * resize_factor)
    if width * height < min_pixels:
        resize_factor = math.sqrt(min_pixels / (width * height))
        width, height = math.ceil(width * resize_factor), math.ceil(height * resize_factor)
    
    return height, width


def smart_resize_uitars(
    height: int, width: int, factor: int = 28, 
    min_pixels: int = 100 * 28 * 28, max_pixels: int = 16384 * 28 * 28,
    max_ratio: int = 200
) -> tuple:
    """
    Rescales image for UITars so that:
    1. Both dimensions are divisible by 'factor'
    2. Total pixels are within [min_pixels, max_pixels]
    3. Aspect ratio is maintained
    """
    return height, width
    if max(height, width) / min(height, width) > max_ratio:
        raise ValueError(
            f"Aspect ratio must be < {max_ratio}, got {max(height, width) / min(height, width)}"
        )
    
    h_bar = max(factor, round_by_factor(height, factor))
    w_bar = max(factor, round_by_factor(width, factor))
    
    if h_bar * w_bar > max_pixels:
        beta = math.sqrt((height * width) / max_pixels)
        h_bar = floor_by_factor(height / beta, factor)
        w_bar = floor_by_factor(width / beta, factor)
    elif h_bar * w_bar < min_pixels:
        beta = math.sqrt(min_pixels / (height * width))
        h_bar = ceil_by_factor(height * beta, factor)
        w_bar = ceil_by_factor(width * beta, factor)
    
    return h_bar, w_bar


def parse_uitars_response(response, origin_height=1080, origin_width=1920):
    """
    Parse UITars response and convert to gym action format.
    
    Args:
        response: Raw model response string
        origin_height: Original screen height
        origin_width: Original screen width
    
    Returns:
        Dict with 'actions' and 'metadata' keys
    """
    IMAGE_FACTOR = 28
    MIN_PIXELS = 100 * 28 * 28
    MAX_PIXELS = 16384 * 28 * 28
    
    text = response.strip()
    
    # Extract thought/reflection
    thought = None
    reflection = None
    if text.startswith("Thought:"):
        thought_pattern = r"Thought: (.+?)(?=\s*Action: |$)"
        thought_hint = "Thought: "
    elif text.startswith("Reflection:"):
        thought_pattern = r"Reflection: (.+?)Action_Summary: (.+?)(?=\s*Action: |$)"
        thought_hint = "Reflection: "
    elif text.startswith("Action_Summary:"):
        thought_pattern = r"Action_Summary: (.+?)(?=\s*Action: |$)"
        thought_hint = "Action_Summary: "
    else:
        thought_pattern = r"Thought: (.+?)(?=\s*Action: |$)"
        thought_hint = "Thought: "
    
    thought_match = re.search(thought_pattern, text, re.DOTALL)
    if thought_match:
        if len(thought_match.groups()) == 1:
            thought = thought_match.group(1).strip()
        elif len(thought_match.groups()) == 2:
            thought = thought_match.group(2).strip()
            reflection = thought_match.group(1).strip()
    
    # Convert point format
    if "<point>" in text:
        text = convert_point_to_coordinates_uitars(text)
    
    # Normalize parameter names
    text = text.replace("start_point=", "start_box=")
    text = text.replace("end_point=", "end_box=")
    text = text.replace("point=", "start_box=")
    
    # Extract action
    if "Action:" not in text:
        # No action found - assume terminate
        return {
            'actions': [],
            'metadata': {
                'thought': thought or "",
                'conclusion': thought or "",
                'action_type': 'terminate',
                'is_terminal': True,
                'wait_time': None
            }
        }
    
    action_str = text.split("Action: ")[-1]
    
    # Parse multiple actions
    tmp_all_action = action_str.split("')\n\n")
    all_action = []
    for action_str in tmp_all_action:
        if "type(content" in action_str:
            def escape_quotes(match):
                content = match.group(1)
                return content
            
            pattern = r"type\(content='(.*?)'\)"
            content = re.sub(pattern, escape_quotes, action_str)
            action_str = escape_single_quotes_uitars(content)
            action_str = "type(content='" + action_str + "')"
        all_action.append(action_str)
    
    # Parse each action
    parsed_actions = [parse_action_uitars(action.replace("\n", "\\n").lstrip()) for action in all_action]
    
    # Convert to gym format
    actions = []
    action_type = None
    
    # Calculate smart resize dimensions for coordinate conversion
    smart_resize_height, smart_resize_width = smart_resize_uitars(
        origin_height, origin_width, 
        factor=IMAGE_FACTOR, min_pixels=MIN_PIXELS, max_pixels=MAX_PIXELS
    )
    
    for action_instance, raw_str in zip(parsed_actions, all_action):
        if action_instance is None:
            print(f"Action can't parse: {raw_str}")
            continue
        
        action_type = action_instance["function"]
        params = action_instance["args"]
        
        # Process coordinates in parameters
        processed_params = {}
        for param_name, param in params.items():
            if param == "":
                continue
            param = str(param).lstrip()
            processed_params[param_name.strip()] = param
            
            if "start_box" in param_name or "end_box" in param_name:
                ori_box = param
                numbers = ori_box.replace("(", "").replace(")", "").split(",")
                
                # Convert to relative coordinates (0-1 range)
                float_numbers = []
                for num_idx, num in enumerate(numbers):
                    num = float(num)
                    if (num_idx + 1) % 2 == 0:  # y coordinate
                        float_numbers.append(float(num / smart_resize_height))
                    else:  # x coordinate
                        float_numbers.append(float(num / smart_resize_width))
                
                if len(float_numbers) == 2:
                    float_numbers = [float_numbers[0], float_numbers[1], 
                                   float_numbers[0], float_numbers[1]]
                
                # Convert to absolute pixels
                x = (float_numbers[0] + float_numbers[2]) / 2 * origin_width
                y = (float_numbers[1] + float_numbers[3]) / 2 * origin_height
                processed_params[param_name.strip() + '_abs'] = [int(x), int(y)]
        
        # Convert action to gym format
        if action_type == "click" or action_type == "left_single":
            if 'start_box_abs' in processed_params:
                x, y = processed_params['start_box_abs']
                actions.append({'mouse': {'left_click': [x, y]}})
        
        elif action_type == "left_double":
            if 'start_box_abs' in processed_params:
                x, y = processed_params['start_box_abs']
                actions.append({'mouse': {'double_click': [x, y]}})
        
        elif action_type == "right_single":
            if 'start_box_abs' in processed_params:
                x, y = processed_params['start_box_abs']
                actions.append({'mouse': {'right_click': [x, y]}})
        
        elif action_type == "hover":
            if 'start_box_abs' in processed_params:
                x, y = processed_params['start_box_abs']
                actions.append({'mouse': {'move': [x, y]}})
        
        elif action_type == "drag" or action_type == "select":
            if 'start_box_abs' in processed_params and 'end_box_abs' in processed_params:
                x1, y1 = processed_params['start_box_abs']
                x2, y2 = processed_params['end_box_abs']
                actions.extend([
                    {'mouse': {'move': [x1, y1]}},
                    {'mouse': {'buttons': {'left_down': True}}},
                    {'mouse': {'move': [x2, y2]}},
                    {'mouse': {'buttons': {'left_up': True}}}
                ])
        
        elif action_type == "hotkey":
            key_str = processed_params.get("key", processed_params.get("hotkey", ""))
            if key_str:
                keys = key_str.split()
                actions.append({'keyboard': {'keys': keys}})
        
        elif action_type == "type":
            content = processed_params.get("content", "")
            if content:
                actions.append({'keyboard': {'text': content}})
        
        elif action_type == "scroll":
            direction = processed_params.get("direction", "down")
            if "up" in direction.lower():
                actions.append({'mouse': {'scroll': 5}})
            elif "down" in direction.lower():
                actions.append({'mouse': {'scroll': -5}})
        
        elif action_type == "wait":
            # Don't add action, set wait_time in metadata
            pass
        
        elif action_type == "finished":
            action_type = "terminate"
    
    # Build metadata
    conclusion = thought or ""
    metadata = {
        'thought': thought or "",
        'conclusion': conclusion,
        'action_type': action_type or 'unknown',
        'is_terminal': action_type == 'finished' or action_type == 'terminate',
        'wait_time': None
    }
    
    if action_type == 'wait':
        metadata['wait_time'] = 1.0  # Default wait time
    
    return {'actions': actions, 'metadata': metadata}


