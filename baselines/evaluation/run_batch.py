import argparse
import json
import os
import random
import subprocess
import sys
import time

from benchmarks.cua_world.registry import get_tasks_for_environment, resolve_environment_dir, resolve_environment_key


parser = argparse.ArgumentParser()
parser.add_argument("--model", type=str, required=False, default="mPLUG/GUI-Owl-32B")
parser.add_argument("--agent", type=str, required=False, default="OwlAgent")
parser.add_argument("--exp_name", type=str, required=False, default="owl-gui-normal-highres-all")
parser.add_argument("--use_cache", action="store_true")
parser.add_argument("--cache_level", type=str, required=False, default="pre_start")
parser.add_argument('--split', type=str, required=False, default="test")
parser.add_argument('--temperature', type=float, required=False, default=1.0)
parser.add_argument('--repeat', type=int, required=False, default=1)
parser.add_argument('--env_dir', type=str, required=False, default="all")
parser.add_argument('--max_steps', type=int, required=False, default=50)
parser.add_argument('--max_tasks', type=int, required=False, default=-1)
parser.add_argument('--max_repetitions', type=int, required=False, default=-1)
parser.add_argument('--surface', type=str, choices=("raw", "verified"), default="raw")
parser.add_argument('--use_savevm', action="store_true", help="Use QEMU savevm to speed up env initialization")
args = parser.parse_args()

MODEL = args.model
EXP_NAME = args.exp_name
AGENT = args.agent
USE_CACHE = args.use_cache
SPLIT = args.split
TEMPERATURE = args.temperature
REPEAT = args.repeat
MAX_STEPS = args.max_steps
CACHE_LEVEL = args.cache_level
MAX_REPETITIONS = args.max_repetitions
USE_SAVEVM = args.use_savevm
SURFACE = args.surface
task_env_pairs = []
env_key = resolve_environment_key(args.env_dir)
env_dir_path = resolve_environment_dir(args.env_dir)

for task_id in get_tasks_for_environment(env_key, split=SPLIT, surface=SURFACE):
    task_env_pairs.append((task_id, str(env_dir_path)))

random.shuffle(task_env_pairs)

if args.max_tasks != -1:
    task_env_pairs = task_env_pairs[:args.max_tasks]

if MAX_REPETITIONS != -1:
    # Sleep for random time between 0 and 10 seconds
    time.sleep(np.random.rand() * 10)

for repeat in range(REPEAT):
    # for task_file in all_tasks:
    print(f"Starting {len(task_env_pairs)} tasks")
    for task_file, env_dir in task_env_pairs:
        # Count number of all_runs/exp_name/model_name/task_file/run_*
        try:
            run_count = len(os.listdir(f"all_runs/{EXP_NAME}/{MODEL}/{task_file}/"))
            print(f"Run count: {run_count} for folder: all_runs/{EXP_NAME}/{MODEL}/{task_file}/")
            if MAX_REPETITIONS != -1 and run_count >= MAX_REPETITIONS:
                continue
        except FileNotFoundError:
            print(f"all_runs/{EXP_NAME}/{MODEL}/{task_file}/ not found")
        print('Starting task: ', task_file)
        agent_args = json.dumps(
            {
                "model": MODEL,
                "exp_name": EXP_NAME,
                "task_name": task_file,
                "temperature": TEMPERATURE,
            }
        )
        command = [
            sys.executable,
            "-m",
            "baselines.evaluation.run_single",
            "--env_dir",
            env_dir,
            "--task",
            task_file,
            "--agent",
            AGENT,
            "--agent_args",
            agent_args,
            "--steps",
            str(MAX_STEPS),
            "--cache_level",
            CACHE_LEVEL,
        ]
        if USE_CACHE:
            command.append("--use_cache")
        if USE_SAVEVM:
            command.append("--use_savevm")
        print(" ".join(command))
        subprocess.run(command, check=False)

        # Make a curl request to localhost:4243/v1, if not available keep exponential backoff sleeping for 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024 seconds
        # if 'claude' in MODEL:  
        #     continue
        # for i in range(15):
        #     try:
        #         response = requests.get("http://localhost:4243/v1")
        #         break
        #     except requests.exceptions.RequestException as e:
        #         print(f'Retrying Attempt {i} for localhost:4243/v1', f'Sleeping for {2**i} seconds')
        #         time.sleep(2**i)
        #     if i == 14: # 15 attempts
        #         raise Exception("Failed to connect to localhost:4243/v1 after 15 attempts")
