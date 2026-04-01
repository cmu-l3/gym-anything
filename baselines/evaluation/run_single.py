import argparse
import json
import os
import time

import baselines.agents as agents
from gym_anything.api import from_config
from tqdm import tqdm


DEFAULT_VLM_BACKEND = os.environ.get("VLM_BACKEND", "local")
DEFAULT_VLM_BASE_URL = os.environ.get("VLM_BASE_URL", "http://localhost:8080/v1")
DEFAULT_VLM_MODEL = os.environ.get("VLM_MODEL", "Qwen/Qwen3-VL-4B-Thinking")

################# ARGUMENT PARSER #################
parser = argparse.ArgumentParser()
parser.add_argument("--env_dir", type=str, required=True)
parser.add_argument("--seed", type=int, default=42)
parser.add_argument("--task", type=str, required=True)
parser.add_argument("--steps", type=int, default=50)
parser.add_argument('--agent', type=str, required=True)
parser.add_argument('--agent_args', type=str, required=True, help='Arguments for the agent, in the form of a dictionary string')
parser.add_argument("--debug", action="store_true")
parser.add_argument("--debug_low", action="store_true")
parser.add_argument("--verbose", action="store_true")
parser.add_argument("--setup_code", type=str, default="auto")
parser.add_argument("--use_cache", action="store_true", help="Use Docker checkpoint cache to speed up env initialization")
parser.add_argument('--cache_level', type=str, default='pre_start', help='Level of cache to use')
parser.add_argument('--use_savevm', action="store_true", help="Use QEMU savevm to speed up env initialization")
parser.add_argument("--vlm_backend", type=str, default=DEFAULT_VLM_BACKEND)
parser.add_argument("--vlm_base_url", type=str, default=DEFAULT_VLM_BASE_URL)
parser.add_argument("--vlm_model", type=str, default=DEFAULT_VLM_MODEL)
args = parser.parse_args()


def _apply_vlm_settings() -> None:
    os.environ["VLM_BACKEND"] = args.vlm_backend
    os.environ["VLM_BASE_URL"] = args.vlm_base_url
    os.environ["VLM_MODEL"] = args.vlm_model


def _resolve_setup_code(env_dir: str, requested: str) -> str:
    return "none" if requested == "none" else requested


_apply_vlm_settings()


################# ENVIRONMENT SETUP #################
env = from_config(args.env_dir, task_id=args.task)
print('Okay now resetting the environment')
# breakpoint()
try:
    print('Resetting the environment')
    obs = env.reset(seed=args.seed, use_cache=args.use_cache, cache_level=args.cache_level, use_savevm=args.use_savevm)
    print('Environment reset successfully')
    setup_code = _resolve_setup_code(args.env_dir, args.setup_code)
    if setup_code != "none":
        succ = env.apply_post_reset_setup(setup_code, steps=args.steps, env_dir=args.env_dir)
        if not succ:
            print('Environment likely not setup correctly, will exit in future')
except Exception as e:
    print('We identified that the docker env wasn\'t setup correctly.')
    print(f"Error setting up environment: {e}")
    env.close()
    exit(1)


print("Episode started. Artifacts will be saved under:", env._episode_dir)
TASK_DESCRIPTION = env.task_spec.description if env.task_spec else None
if not TASK_DESCRIPTION:
    task_spec_path = (env._task_root / "task.json") if getattr(env, "_task_root", None) else None
    if task_spec_path is None:
        task_spec_path = os.path.join(args.env_dir, "tasks", args.task, "task.json")
    with open(task_spec_path, 'r', encoding='utf-8') as task_file:
        TASK_DESCRIPTION = json.load(task_file).get('description')

################# Agent Setup #################
agent = getattr(agents, args.agent)(agent_args=json.loads(args.agent_args), verbose=args.verbose, debug=args.debug)

# TODO: Make sure all and correct details are being passed to the agent
agent.init(task_description=TASK_DESCRIPTION, display_resolution=env.env_spec.observation[0].resolution, save_path = env._episode_dir)

################# Agent Loop #################
action_outputs = []
obs = env.capture_observation()
done = False
max_steps = env.max_steps or args.steps
# TODO: Currently the *3 is a heuristic cap for agent/tool interaction loops.
for step_i in tqdm(range(max_steps * 3)):
    profile_start_time = time.time()
    actions = agent.step(obs, action_outputs)
    print(f'[baselines.evaluation.run_single] Profiling time for agent.step: {time.time() - profile_start_time}', actions)
    action_outputs = []
    # if args.debug:
    #     breakpoint()
    if args.debug:
        breakpoint()
    for action in actions:
        # Actual action execution
        actual_actions = action['actions']
        # TODO: Currently we assume that if there is a screenshot action, it is the only action
        if len(actual_actions) == 1 and 'action' in actual_actions[0] and actual_actions[0]['action'] == 'screenshot':
            profile_capture_observation_time = time.time()
            obs = env.capture_observation()
            print(f'[baselines.evaluation.run_single] Profiling time for env.capture_observation: {time.time() - profile_capture_observation_time}')
            action_outputs.append(
                {
                    'action': 'screenshot',
                    'output': obs['screen']['path'],
                    'tool_id': action['tool_id'],
                }
            )
        elif len(actual_actions) == 1 and 'action' in actual_actions[0] and actual_actions[0]['action'] == 'wait':
            wait_time = actual_actions[0]['time']
            time.sleep(wait_time)
            action_outputs.append({
                'action': 'wait',
                'output': 'Waited for {} seconds'.format(wait_time),
                'tool_id': action['tool_id'],
            })
            obs = env.capture_observation()
        else:
            if args.debug:
                breakpoint()
            profile_step_time = time.time()
            obs, reward, done, info = env.step(actual_actions)
            print(f'[baselines.evaluation.run_single] Profiling time for env.step: {time.time() - profile_step_time}')
            action_outputs.append({
                'action' : 'other',
                'output' : "Executed the action",
                'tool_id': action['tool_id'],
            })
        # TODO: Currently step logic of env is bit wrong, since it is dependent on how many times we call step, instead of how many times the interaction with agent takes place. Fix this.
    
    if agent.done or done:
        # breakpoint()
        # TODO: Probably change it to empty action?
        obs, reward, done, info = env.step(actual_actions, mark_done=True)
        break

if args.debug_low or args.debug:
    breakpoint()
# breakpoint()
EPISODE_DIR = env._episode_dir
print("Episode finished. See:", EPISODE_DIR, 'info:', info)
if args.debug:
    breakpoint()
env.close()

if 'verifier' in info and info['verifier'] is None:
    # Maybe we try loading the summary.json from episode_dir
    try:
        info = json.load(open(f'{EPISODE_DIR}/summary.json'))
    except Exception as e:
        print(f"Error loading summary.json: {e}")
agent.finish(info=info)
