from pathlib import Path
import sys

_repo_root = Path(__file__).resolve().parents[2]
if str(_repo_root) not in sys.path:
    sys.path.insert(0, str(_repo_root))
_src_dir = _repo_root / "src"
if _src_dir.is_dir() and str(_src_dir) not in sys.path:
    sys.path.insert(0, str(_src_dir))

from PIL import Image
from io import BytesIO
import base64

import json
import os
from glob import glob
import time

from baselines.common.llm_clients import call_gemini_with_retry, call_claude_with_retry, call_claude, call_claude_databricks

# print(response[0].content)

def encode_image(image_path):
    image = Image.open(image_path)
    # image = image.resize((1280, 720))
    buffer = BytesIO()
    image.save(buffer, format="PNG")
    processed_bytes = buffer.getvalue()
    return f'data:image/png;base64,{base64.b64encode(processed_bytes).decode("utf-8")}'

def get_messages(task_description, model_responses, images, image_step_interval=10):
    messages = [
        {
            'role': 'system',
            'content': 'You are a helpful assistant that looks through trajectory of an agent interacting with a computer-use software, and identify whether the task was completed correctly or not. You will be provided with both the screenshots of the full trajectory, as well as model actions. You will also be provided with task description that the agent was trying to solve.'
        },
        {
            'role': 'user',
            'content': [
                {
                    'type': 'text',
                    'text': "Here is the task description: " + task_description
                }
            ]
        },
        # {
        #     'role': 'user',
        #     'content': [
        #         {
        #             'type': 'text',
        #             'text': "Here are the steps taken by the agent: " + '\n\n'.join([f'Step {i+1}: {x}' for i, x in enumerate(model_responses)])
        #         }
        #     ]
        # },
        {
            'role': 'user',
            'content': [
                {
                    'type': 'text',
                    'text': 'Here are the screenshots of the full trajectory (note, images are provided every 3 steps + first 3 and last 3 steps): '
                }
            ] + [
                {
                    'type': 'image_url',
                    'image_url': {
                        'url': encode_image(x)
                    }
                }
                for x in images[:3] + images[3:-3][::image_step_interval] + images[-3:]
                # for x in images[3:-3][::image_step_interval]


            ]
        },
        {
            'role': 'user',
            'content': [
                {
                    'type': 'text',
                    'text': f'''Based on the trajectory and task description: ```{task_description}```, identify whether original task correctly solved? Was there any points where the agent lied? Was environment used to solve task, or was the task completed using knowledge? Did the agent cheat at any point? Give your final answer in a json format, with keys: "solved': "true/false/partial", "reasoning": "<your_explanation>"'''
                }
            ]
        }
    ]
    return messages

if len(sys.argv) < 3 or sys.argv[1] in {"-h", "--help"}:
    print(
        "Usage: python tools/verification/verify_all_tasks_gemini.py "
        "<run_folder> <env_name>"
    )
    raise SystemExit(0 if len(sys.argv) >= 2 and sys.argv[1] in {"-h", "--help"} else 1)

folder_main = sys.argv[1]
env_name = sys.argv[2]
# FOLDERS = glob('all_runs/qwen3vl_envs_test/Qwen/Qwen3-VL-4B-Thinking/*/run_0/')
FOLDERS = glob(f'all_runs/{folder_main}/*/*/run_*/')
if len(FOLDERS) == 0:
    # Try adding another *
    FOLDERS = glob(f'all_runs/{folder_main}/*/*/*/run_*/')
    if len(FOLDERS) == 0:
        raise ValueError(f"No folders found for {folder_main}")
# FOLDERS = glob('all_runs/gemini3_pro_initial_distillations_openemr/*/*/run_*/')

judge_responses = []
from tqdm import tqdm
import multiprocessing
# for FOLDER in tqdm(glob(FOLDERS)):

def get_judge_response(FOLDER, VLM_MODEL='gemini-3-flash-preview'):
    task_name = FOLDER.split('/')[-3]
    try:
        model_responses = json.load(open(os.path.join(FOLDER, 'responses.json')))['model_responses']
        images = [x for x in sorted(glob(os.path.join(FOLDER, f'observation_*.png')), key=lambda x: int(x.split('_')[-1].split('.')[0]))]
        task_description = json.load(open(f"benchmarks/environments/{env_name}/tasks/{task_name}/task.json"))['description']
        info_file = json.load(open(os.path.join(FOLDER, 'info.json')))
        if 'vlm_verifier' in info_file:
            return ''

    except FileNotFoundError:
        return ''
    messages = get_messages(task_description, model_responses, images, image_step_interval=3)
    for retry in range(5):
        try:
            response = call_gemini_with_retry(messages, VLM_MODEL, temperature=1.0, top_p=0.95)
            # response = call_claude(messages, VLM_MODEL, temperature=1.0, top_p=0.95)
            # response = call_claude_databricks(messages, VLM_MODEL, temperature=1.0, top_p=0.95)
            # breakpoint()
            json_response = json.loads(response.split('</think>')[-1].split('```json')[1].split('```')[0].strip())
            break
        except Exception as e:
            print(f"Error in retry {retry}: {e}")
            time.sleep(retry**2 * 5)
            continue
    if 'vlm_verifier' not in info_file:
        info_file['vlm_verifier'] = []
    info_file['vlm_verifier'].append({
        'full_response': response,
        'model': VLM_MODEL,
        'json_response': json.dumps(json_response),
        'is_solved': json_response['solved'],
    })
    with open(os.path.join(FOLDER, 'info.json'), 'w') as f:
        json.dump(info_file, f, indent=4)
    return response
with multiprocessing.Pool(16) as p:
    judge_responses = list(tqdm(p.imap(get_judge_response, FOLDERS), total=len(FOLDERS)))
# for folder in FOLDERS:
#     get_judge_response(folder, VLM_MODEL='gemini-3-pro-preview')
#     print(folder)

# breakpoint()
