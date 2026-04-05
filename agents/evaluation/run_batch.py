from __future__ import annotations

import argparse
import json
import os
import random
import subprocess
import sys
import time

from benchmarks.cua_world.registry import (
    get_tasks_for_environment,
    load_environment_task_splits,
    resolve_environment_dir,
    resolve_environment_key,
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=str, default="mPLUG/GUI-Owl-32B")
    parser.add_argument("--agent", type=str, default="OwlAgent")
    parser.add_argument("--exp_name", type=str, default="owl-gui-normal-highres-all")
    parser.add_argument("--use_cache", action="store_true")
    parser.add_argument("--cache_level", type=str, default="pre_start")
    parser.add_argument("--split", type=str, default="test")
    parser.add_argument("--temperature", type=float, default=1.0)
    parser.add_argument("--repeat", type=int, default=1)
    parser.add_argument("--env_dir", type=str, default="all")
    parser.add_argument("--max_steps", type=int, default=50)
    parser.add_argument("--max_tasks", type=int, default=-1)
    parser.add_argument("--max_repetitions", type=int, default=-1)
    parser.add_argument("--surface", type=str, choices=("raw", "verified"), default="raw")
    parser.add_argument("--use_savevm", action="store_true", help="Use QEMU savevm to speed up env initialization")
    return parser


def _build_task_env_pairs(args: argparse.Namespace) -> list[tuple[str, str]]:
    pairs: list[tuple[str, str]] = []
    if args.env_dir == "all":
        registry = load_environment_task_splits(surface=args.surface)
        for env_key, split_map in registry.items():
            if args.split not in split_map:
                continue
            env_dir = resolve_environment_dir(env_key)
            for task_id in split_map[args.split]:
                pairs.append((task_id, str(env_dir)))
        return pairs

    env_key = resolve_environment_key(args.env_dir)
    env_dir_path = resolve_environment_dir(args.env_dir)
    for task_id in get_tasks_for_environment(env_key, split=args.split, surface=args.surface):
        pairs.append((task_id, str(env_dir_path)))
    return pairs


def run_batch(args: argparse.Namespace) -> int:
    task_env_pairs = _build_task_env_pairs(args)
    random.shuffle(task_env_pairs)

    if args.max_tasks != -1:
        task_env_pairs = task_env_pairs[: args.max_tasks]

    if args.max_repetitions != -1:
        time.sleep(random.random() * 10)

    for _repeat in range(args.repeat):
        print(f"Starting {len(task_env_pairs)} tasks")
        for task_id, env_dir in task_env_pairs:
            run_root = f"all_runs/{args.exp_name}/{args.model}/{task_id}/"
            try:
                run_count = len(os.listdir(run_root))
                print(f"Run count: {run_count} for folder: {run_root}")
                if args.max_repetitions != -1 and run_count >= args.max_repetitions:
                    continue
            except FileNotFoundError:
                print(f"{run_root} not found")

            print("Starting task:", task_id)
            agent_args = json.dumps(
                {
                    "model": args.model,
                    "exp_name": args.exp_name,
                    "task_name": task_id,
                    "temperature": args.temperature,
                }
            )
            command = [
                sys.executable,
                "-m",
                "agents.evaluation.run_single",
                "--env_dir",
                env_dir,
                "--task",
                task_id,
                "--agent",
                args.agent,
                "--agent_args",
                agent_args,
                "--steps",
                str(args.max_steps),
                "--cache_level",
                args.cache_level,
            ]
            if args.use_cache:
                command.append("--use_cache")
            if args.use_savevm:
                command.append("--use_savevm")
            print(" ".join(command))
            subprocess.run(command, check=False)

    return 0


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return run_batch(args)


if __name__ == "__main__":
    raise SystemExit(main())
