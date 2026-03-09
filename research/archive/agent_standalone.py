from gym_anything.api import from_config
import time
import argparse
from PIL import Image
from io import BytesIO
import json
# from agent_prompts import SYSTEM_PROMPT, USER_PROMPT
from baselines.common.llm_clients import get_prompt, pil_to_base64, call_llm, parse_owl_response


parser = argparse.ArgumentParser()
parser.add_argument("--env_dir", type=str, required=True)
parser.add_argument("--task", type=str, required=True)
parser.add_argument("--seed", type=int, default=42)
parser.add_argument("--steps", type=int, default=15)
parser.add_argument("--model", type=str, default="mPLUG/GUI-Owl-32B")
parser.add_argument("--temperature", type=float, default=0.6)
parser.add_argument("--top_p", type=float, default=0.9)
parser.add_argument("--debug", action="store_true")
parser.add_argument("--base_url", type=str, default="http://localhost:4243/v1")
args = parser.parse_args()

# messages = []



#### Environment Setup
env = from_config(args.env_dir, task_id=args.task)
print("Episode started. Artifacts will be saved under:", env._episode_dir)
steps = args.steps or (env.task_spec.init.max_steps if env.task_spec else 10)
env._max_steps = steps

breakpoint()

########################################################

obs = env.reset(seed=args.seed)


def make_display_full_screen(window_string = 'GIMP'):
    time.sleep(1)
    env._runner.exec("DISPLAY=:1 xdotool mousemove --sync 800 600 click 1")
    time.sleep(1)
    # TODO: Use the window_string
    wid = env._runner.exec_capture("wmctrl -l | grep -i 'GIMP' | awk '{print $1; exit}'").strip()
    time.sleep(1)
    env._runner.exec(f"DISPLAY=:1 wmctrl -ia {wid}")
    time.sleep(1)
    env._runner.exec("DISPLAY=:1 xdotool key --delay 200 F11")
    time.sleep(1)

make_display_full_screen()

TASK_DESCRIPTION = json.load(open(f'{args.env_dir}/tasks/{args.task}/task.json'))['description']

all_model_responses = []
all_parsed_responses = []

history = []
for i in range(steps):
    if i == env._max_steps - 1 and args.debug:
        breakpoint()
    if args.debug:
        breakpoint()
    messages = get_prompt(TASK_DESCRIPTION, history)
    messages[-1]['content'].append({"type": "text", "text": "Current screenshot:\n"})
    obs = env._capture_observation()
    image = Image.open(obs['screen']['path'])
    encoded_string = pil_to_base64(image)

    messages[-1]['content'].append({"type": "image_url", "image_url": {"url": f"data:image/png;base64,{encoded_string}"}})


    response = call_llm(messages, args.model, args.temperature, args.top_p)

    parsed_response = parse_owl_response(response)
    all_model_responses.append(response)
    all_parsed_responses.append(parsed_response)

    actions = parsed_response['actions']
    metadata = parsed_response['metadata']
    history.append("Step {}: {}".format(i+1, metadata['conclusion']))

    if args.debug:
        breakpoint()

    if metadata['is_terminal']:
        env._max_steps = i + 1
        obs, reward, done, info = env.step(actions)
        print("Episode finished. See:", env._episode_dir, 'info:', info)
        break
    else:
        if 'wait_time' in metadata and metadata['wait_time'] is not None:
            time.sleep(metadata['wait_time'])
            obs, reward, done, info = env.step({})
        else:
            obs, reward, done, info = env.step(actions)
    
    
    if done:
        break
    time.sleep(0.2)
if args.debug:
    breakpoint()



print("Episode finished. See:", env._episode_dir, 'info:', info)
EPISODE_DIR = env._episode_dir
env.close()

json.dump({'model_responses': all_model_responses, 'parsed_responses': all_parsed_responses}, open(f'{EPISODE_DIR}/responses.json', 'w'), indent=4)
json.dump(all_parsed_responses, open(f'{EPISODE_DIR}/parsed_responses.json', 'w'), indent=4)
