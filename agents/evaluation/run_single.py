from __future__ import annotations

import argparse
import json
import logging
import os
from pathlib import Path

import agents.agents as agent_registry
from gym_anything.api import from_config
from gym_anything.remote import RemoteGymEnv
from tqdm import tqdm


DEFAULT_VLM_BACKEND = os.environ.get("VLM_BACKEND", "local")
DEFAULT_VLM_BASE_URL = os.environ.get("VLM_BASE_URL", "http://localhost:8080/v1")
DEFAULT_VLM_MODEL = os.environ.get("VLM_MODEL", "Qwen/Qwen3-VL-4B-Thinking")
logger = logging.getLogger(__name__)


_VERIFIER_CLI_ENV = {
    "vlm_checklist_model": "GYM_ANYTHING_VLM_CHECKLIST_MODEL",
    "vlm_checklist_backend": "GYM_ANYTHING_VLM_CHECKLIST_BACKEND",
    "vlm_checklist_base_url": "GYM_ANYTHING_VLM_CHECKLIST_BASE_URL",
    "vlm_checklist_temperature": "GYM_ANYTHING_VLM_CHECKLIST_TEMPERATURE",
    "vlm_checklist_top_p": "GYM_ANYTHING_VLM_CHECKLIST_TOP_P",
    "vlm_checklist_max_tokens": "GYM_ANYTHING_VLM_CHECKLIST_MAX_TOKENS",
    "vlm_checklist_max_frames": "GYM_ANYTHING_VLM_CHECKLIST_MAX_FRAMES",
    "vlm_checklist_completion_threshold": "GYM_ANYTHING_VLM_CHECKLIST_COMPLETION_THRESHOLD",
    "vlm_checklist_integrity_threshold": "GYM_ANYTHING_VLM_CHECKLIST_INTEGRITY_THRESHOLD",
}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env_dir", type=str, required=True)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--task", type=str, required=True)
    parser.add_argument("--steps", type=int, default=None)
    parser.add_argument("--agent", type=str, required=True)
    parser.add_argument(
        "--agent_args",
        type=str,
        required=True,
        help="Arguments for the agent, in the form of a dictionary string",
    )
    parser.add_argument("--debug", action="store_true")
    parser.add_argument("--debug_low", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--setup_code", type=str, default="auto")
    parser.add_argument(
        "--use_cache",
        action="store_true",
        help="Use Docker checkpoint cache to speed up env initialization",
    )
    parser.add_argument("--cache_level", type=str, default="pre_start", help="Level of cache to use")
    parser.add_argument(
        "--use_savevm",
        action="store_true",
        help="Use QEMU savevm to speed up env initialization",
    )
    parser.add_argument("--vlm_backend", type=str, default=DEFAULT_VLM_BACKEND)
    parser.add_argument("--vlm_base_url", type=str, default=DEFAULT_VLM_BASE_URL)
    parser.add_argument("--vlm_model", type=str, default=DEFAULT_VLM_MODEL)
    parser.add_argument(
        "--verifier_mode",
        choices=("task", "program", "image_match", "multi", "vlm_checklist"),
        default=None,
        help="Override task.json success.mode for this run. Use 'task' to force task.json behavior.",
    )
    parser.add_argument("--vlm_checklist_model", type=str, default=None)
    parser.add_argument("--vlm_checklist_backend", choices=("local", "openai", "anthropic", "gemini"), default=None)
    parser.add_argument("--vlm_checklist_base_url", type=str, default=None)
    parser.add_argument("--vlm_checklist_temperature", type=float, default=None)
    parser.add_argument("--vlm_checklist_top_p", type=float, default=None)
    parser.add_argument("--vlm_checklist_max_tokens", type=int, default=None)
    parser.add_argument("--vlm_checklist_max_frames", type=int, default=None)
    parser.add_argument("--vlm_checklist_completion_threshold", type=float, default=None)
    parser.add_argument("--vlm_checklist_integrity_threshold", type=float, default=None)
    parser.add_argument("--remote_url", type=str, default=None, help="Remote master or worker URL")
    parser.add_argument("--remote_timeout", type=int, default=300, help="Remote HTTP request timeout")
    parser.add_argument(
        "--remote_worker_reset_policy",
        choices=("core", "baseline_setup", "none"),
        default="core",
        help="Worker-local reset policy for remote environments",
    )
    return parser


def _apply_vlm_settings(args: argparse.Namespace) -> None:
    os.environ["VLM_BACKEND"] = args.vlm_backend
    os.environ["VLM_BASE_URL"] = args.vlm_base_url
    os.environ["VLM_MODEL"] = args.vlm_model


def _apply_verifier_settings(args: argparse.Namespace) -> None:
    mode = getattr(args, "verifier_mode", None)
    if mode is not None:
        if mode == "task":
            os.environ["GYM_ANYTHING_VERIFIER_MODE"] = "task"
        else:
            os.environ["GYM_ANYTHING_VERIFIER_MODE"] = mode
    for attr, env_var in _VERIFIER_CLI_ENV.items():
        value = getattr(args, attr, None)
        if value is not None:
            os.environ[env_var] = str(value)


def _configure_logging() -> None:
    if logging.getLogger().handlers:
        return
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    )


def _resolve_setup_code(env_dir: str, requested: str) -> str:
    del env_dir
    return "none" if requested == "none" else requested


def _load_task_description(env, env_dir: str, task_id: str) -> str | None:
    if env.task_spec and env.task_spec.description:
        return env.task_spec.description

    task_root = getattr(env, "task_root", None)
    task_spec_path = (task_root / "task.json") if task_root else None
    if task_spec_path is None:
        task_spec_path = Path(env_dir) / "tasks" / task_id / "task.json"

    with open(task_spec_path, "r", encoding="utf-8") as task_file:
        return json.load(task_file).get("description")


def _make_env(args: argparse.Namespace):
    remote_url = getattr(args, "remote_url", None)
    if not remote_url:
        return from_config(args.env_dir, task_id=args.task)
    worker_reset_policy = getattr(args, "remote_worker_reset_policy", "core")
    if worker_reset_policy == "none":
        worker_reset_policy = None
    return RemoteGymEnv.from_config(
        remote_url=remote_url,
        env_dir=args.env_dir,
        task_id=args.task,
        timeout=getattr(args, "remote_timeout", 300),
        worker_reset_policy=worker_reset_policy,
    )


def run_single(args: argparse.Namespace) -> int:
    _apply_vlm_settings(args)
    _apply_verifier_settings(args)

    env = _make_env(args)
    try:
        logger.info("Resetting environment")
        env.reset(
            seed=args.seed,
            use_cache=args.use_cache,
            cache_level=args.cache_level,
            use_savevm=args.use_savevm,
        )
        # Resolve max_steps: CLI arg wins, then task.json, then hard default.
        # Also hard-code the timeout so only step-based stopping applies.
        resolved_max_steps = args.steps or env.max_steps or 50
        env.set_episode_limits(max_steps=resolved_max_steps, timeout_sec=86400)
        logger.info("Environment reset successfully")
    except Exception as exc:
        logger.error("Error setting up environment: %s", exc)
        env.close()
        return 1

    logger.info("Episode started. Artifacts will be saved under: %s", env.episode_dir)
    task_description = _load_task_description(env, args.env_dir, args.task)
    if task_description:
        task_description += "\nUnless explicitly mentioned, you are required to use the UI to complete the task not terminal."

    agent_cls = getattr(agent_registry, args.agent)
    agent = agent_cls(agent_args=json.loads(args.agent_args), verbose=args.verbose, debug=args.debug)
    agent.init(
        task_description=task_description,
        display_resolution=env.env_spec.observation[0].resolution,
        save_path=env.episode_dir,
    )

    action_outputs = []
    obs = env.capture_observation()
    done = False
    info = {}
    max_steps = env.max_steps
    episode_dir = env.episode_dir

    try:
        for _step_i in tqdm(range(max_steps)):
            actions = agent.step(obs, action_outputs)
            action_outputs = []

            for action in actions:
                actual_actions = action["actions"]
                obs, _reward, done, info = env.step(actual_actions)
                action_result = info.get(
                    "action_result",
                    {
                        "action": "other",
                        "output": "Executed the action",
                    },
                )
                action_outputs.append(
                    {
                        **action_result,
                        "tool_id": action["tool_id"],
                        # Per-action observation, captured after THIS tool_use's
                        # env.step. Agents that want per-action visual feedback
                        # (e.g. ClaudeFixedAgent, matching the official
                        # computer-use loop) attach this image to the matching
                        # tool_result. Agents that only consume the final
                        # observation can keep using the `obs` argument to
                        # agent.step and ignore this field.
                        "obs": obs,
                    }
                )

            if getattr(agent, "done", False) or done:
                obs, _reward, done, info = env.step([], mark_done=True)
                break


        episode_dir = env.episode_dir
        logger.info("Episode finished. See: %s info: %s", episode_dir, info)
    finally:
        env.close()

    if "verifier" in info and info["verifier"] is None:
        try:
            with open(f"{episode_dir}/summary.json", "r", encoding="utf-8") as handle:
                info = json.load(handle)
        except Exception as exc:
            logger.warning("Error loading summary.json: %s", exc)

    agent.finish(info=info)
    return 0


def main(argv: list[str] | None = None) -> int:
    _configure_logging()
    parser = build_parser()
    args = parser.parse_args(argv)
    return run_single(args)


if __name__ == "__main__":
    raise SystemExit(main())
