from __future__ import annotations

import argparse
import json
import logging
import os
import statistics
import time
from pathlib import Path
from typing import Any

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
    parser.add_argument(
        "--fast_io",
        "--fast-io",
        action="store_true",
        help="Enable runner-native fast screenshot/input paths.",
    )
    parser.add_argument(
        "--disable_thinking",
        "--disable-thinking",
        action="store_true",
        help="Pass chat_template_kwargs.enable_thinking=false to OpenAI-compatible VLM calls.",
    )
    parser.add_argument(
        "--timing_jsonl",
        "--timing-jsonl",
        type=str,
        default=None,
        help="Optional path for per-iteration timing JSONL. Defaults to <episode_dir>/timing.jsonl.",
    )
    parser.add_argument(
        "--post_reset_observation_delay",
        "--post-reset-observation-delay",
        type=float,
        default=0.0,
        help="Seconds to wait after env.reset before capturing the first model observation.",
    )
    parser.add_argument(
        "--post_step_observation_delay",
        "--post-step-observation-delay",
        type=float,
        default=0.0,
        help="Seconds to wait after each env.step before refreshing the observation for the next model turn.",
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
    if getattr(args, "disable_thinking", False):
        os.environ["VLM_DISABLE_THINKING"] = "1"


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
    fast_io = bool(getattr(args, "fast_io", False))
    remote_url = getattr(args, "remote_url", None)
    if not remote_url:
        return from_config(args.env_dir, task_id=args.task, fast_io=fast_io)
    worker_reset_policy = getattr(args, "remote_worker_reset_policy", "core")
    if worker_reset_policy == "none":
        worker_reset_policy = None
    return RemoteGymEnv.from_config(
        remote_url=remote_url,
        env_dir=args.env_dir,
        task_id=args.task,
        timeout=getattr(args, "remote_timeout", 300),
        worker_reset_policy=worker_reset_policy,
        fast_io=fast_io,
    )


def _elapsed_ms(start: float) -> float:
    return (time.perf_counter() - start) * 1000.0


def _write_timing_record(path: Path, record: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, default=str) + "\n")


def _nonnegative_seconds(args: argparse.Namespace, name: str) -> float:
    value = getattr(args, name, 0.0) or 0.0
    return max(0.0, float(value))


def _screen_output_from_observation(obs: dict[str, Any]) -> Any:
    screen = obs.get("screen", {}) if isinstance(obs, dict) else {}
    if isinstance(screen, dict) and "image" in screen:
        return screen["image"]
    if isinstance(screen, dict):
        return screen.get("path")
    return None


def _refresh_observation_after_delay(env, delay_seconds: float) -> tuple[dict[str, Any] | None, float | None, float | None]:
    if delay_seconds <= 0:
        return None, None, None
    t0 = time.perf_counter()
    time.sleep(delay_seconds)
    delay_ms = _elapsed_ms(t0)
    t0 = time.perf_counter()
    obs = env.capture_observation()
    capture_ms = _elapsed_ms(t0)
    return obs, delay_ms, capture_ms


def _series_stats(series: list[float]) -> dict[str, float | int | None]:
    if not series:
        return {"count": 0, "mean_ms": None, "p50_ms": None, "p95_ms": None, "max_ms": None}
    ordered = sorted(series)
    p95_index = min(len(ordered) - 1, int(0.95 * (len(ordered) - 1)))
    return {
        "count": len(series),
        "mean_ms": statistics.fmean(series),
        "p50_ms": statistics.median(series),
        "p95_ms": ordered[p95_index],
        "max_ms": max(series),
    }


def _timing_summary(records: list[dict[str, Any]]) -> dict[str, Any]:
    def values(key: str) -> list[float]:
        return [float(record[key]) for record in records if record.get(key) is not None]

    llm_values = []
    env_action_values = []
    env_terminal_values = []
    mark_done_values = []
    post_step_observation_values = []
    for record in records:
        agent_internal = record.get("agent_internal_ms") or {}
        if isinstance(agent_internal, dict) and agent_internal.get("llm_call_ms") is not None:
            llm_values.append(float(agent_internal["llm_call_ms"]))
        for env_step in record.get("env_steps", []):
            if env_step.get("post_step_observation_total_ms") is not None:
                post_step_observation_values.append(float(env_step["post_step_observation_total_ms"]))
            if env_step.get("tool_id") == "mark_done":
                mark_done_values.append(float(env_step["env_step_ms"]))
            elif env_step.get("done"):
                env_terminal_values.append(float(env_step["env_step_ms"]))
            else:
                env_action_values.append(float(env_step["env_step_ms"]))

    return {
        "iterations": len(records),
        "agent_step": _series_stats(values("agent_step_ms")),
        "env_step": _series_stats(values("env_step_total_ms")),
        "env_action_step": _series_stats(env_action_values),
        "env_terminal_step": _series_stats(env_terminal_values),
        "mark_done_step": _series_stats(mark_done_values),
        "post_step_observation": _series_stats(post_step_observation_values),
        "iteration_total": _series_stats(values("iteration_total_ms")),
        "llm_call": _series_stats(llm_values),
    }


def _action_kinds(actions: list[dict[str, Any]]) -> list[str]:
    kinds = []
    for action in actions:
        if not isinstance(action, dict):
            kinds.append(type(action).__name__)
            continue
        if "action" in action:
            kinds.append(str(action["action"]))
        elif "mouse" in action:
            kinds.append("mouse")
        elif "keyboard" in action:
            kinds.append("keyboard")
        else:
            kinds.append("other")
    return kinds


def run_single(args: argparse.Namespace) -> int:
    _apply_vlm_settings(args)
    _apply_verifier_settings(args)

    setup_timings: dict[str, float] = {}
    overall_start = time.perf_counter()
    t0 = time.perf_counter()
    env = _make_env(args)
    setup_timings["make_env_ms"] = _elapsed_ms(t0)
    try:
        logger.info("Resetting environment")
        t0 = time.perf_counter()
        env.reset(
            seed=args.seed,
            use_cache=args.use_cache,
            cache_level=args.cache_level,
            use_savevm=args.use_savevm,
        )
        setup_timings["reset_ms"] = _elapsed_ms(t0)
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
    timing_path = Path(getattr(args, "timing_jsonl", None) or Path(env.episode_dir) / "timing.jsonl")
    _write_timing_record(
        timing_path,
        {
            "event": "setup",
            "fast_io": bool(getattr(args, "fast_io", False)),
            "disable_thinking": bool(getattr(args, "disable_thinking", False)),
            **setup_timings,
        },
    )
    task_description = _load_task_description(env, args.env_dir, args.task)

    agent_cls = getattr(agent_registry, args.agent)
    agent = agent_cls(agent_args=json.loads(args.agent_args), verbose=args.verbose, debug=args.debug)
    agent.init(
        task_description=task_description,
        display_resolution=env.env_spec.observation[0].resolution,
        save_path=env.episode_dir,
    )

    action_outputs = []
    post_reset_observation_delay = _nonnegative_seconds(args, "post_reset_observation_delay")
    if post_reset_observation_delay > 0:
        t0 = time.perf_counter()
        time.sleep(post_reset_observation_delay)
        post_reset_delay_ms = _elapsed_ms(t0)
        _write_timing_record(
            timing_path,
            {
                "event": "post_reset_observation_delay",
                "requested_ms": post_reset_observation_delay * 1000.0,
                "actual_ms": post_reset_delay_ms,
            },
        )
    t0 = time.perf_counter()
    obs = env.capture_observation()
    initial_capture_ms = _elapsed_ms(t0)
    _write_timing_record(timing_path, {"event": "initial_capture", "capture_observation_ms": initial_capture_ms})
    logger.info("Initial capture_observation completed in %.2f ms", initial_capture_ms)
    done = False
    info = {}
    max_steps = env.max_steps
    episode_dir = env.episode_dir
    iteration_records: list[dict[str, Any]] = []
    env_step_kwargs = {"wait_between_actions": 0.0} if getattr(args, "fast_io", False) else {}
    post_step_observation_delay = _nonnegative_seconds(args, "post_step_observation_delay")

    try:
        for _step_i in tqdm(range(max_steps)):
            iteration_start = time.perf_counter()
            t0 = time.perf_counter()
            actions = agent.step(obs, action_outputs)
            agent_step_ms = _elapsed_ms(t0)
            agent_internal = getattr(agent, "last_step_timing", None)
            action_outputs = []
            env_step_records = []

            for action_group_i, action in enumerate(actions):
                actual_actions = action["actions"]
                t0 = time.perf_counter()
                obs, _reward, done, info = env.step(actual_actions, **env_step_kwargs)
                env_step_ms = _elapsed_ms(t0)
                refreshed_obs, post_step_delay_ms, post_step_capture_ms = _refresh_observation_after_delay(
                    env,
                    post_step_observation_delay,
                )
                if refreshed_obs is not None:
                    obs = refreshed_obs
                    action_result = info.get("action_result")
                    if isinstance(action_result, dict) and action_result.get("action") == "screenshot":
                        action_result["output"] = _screen_output_from_observation(obs)
                post_step_observation_total_ms = (
                    None
                    if post_step_delay_ms is None or post_step_capture_ms is None
                    else post_step_delay_ms + post_step_capture_ms
                )
                env_step_records.append(
                    {
                        "group_index": action_group_i,
                        "tool_id": action.get("tool_id"),
                        "action_count": len(actual_actions),
                        "action_kinds": _action_kinds(actual_actions),
                        "env_step_ms": env_step_ms,
                        "post_step_observation_delay_ms": post_step_delay_ms,
                        "post_step_observation_capture_ms": post_step_capture_ms,
                        "post_step_observation_total_ms": post_step_observation_total_ms,
                        "done": done,
                        "reason": info.get("reason"),
                        "verifier_present": "verifier" in info,
                    }
                )
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
                    }
                )

            mark_done_step_ms = None
            if getattr(agent, "done", False) or done:
                t0 = time.perf_counter()
                obs, _reward, done, info = env.step([], mark_done=True, **env_step_kwargs)
                mark_done_step_ms = _elapsed_ms(t0)
                env_step_records.append(
                    {
                        "group_index": len(env_step_records),
                        "tool_id": "mark_done",
                        "action_count": 0,
                        "action_kinds": [],
                        "env_step_ms": mark_done_step_ms,
                        "done": done,
                        "reason": info.get("reason"),
                        "verifier_present": "verifier" in info,
                    }
                )
                env_step_total_ms = sum(record["env_step_ms"] for record in env_step_records)
                env_step_action_total_ms = sum(
                    record["env_step_ms"] for record in env_step_records if record["tool_id"] != "mark_done"
                )
                post_step_observation_total_ms = sum(
                    record.get("post_step_observation_total_ms") or 0.0
                    for record in env_step_records
                )
                iteration_total_ms = _elapsed_ms(iteration_start)
                record = {
                    "event": "iteration",
                    "step": _step_i,
                    "agent_step_ms": agent_step_ms,
                    "agent_internal_ms": agent_internal,
                    "env_step_total_ms": env_step_total_ms,
                    "env_step_action_total_ms": env_step_action_total_ms,
                    "post_step_observation_total_ms": post_step_observation_total_ms,
                    "env_steps": env_step_records,
                    "mark_done_step_ms": mark_done_step_ms,
                    "iteration_total_ms": iteration_total_ms,
                }
                iteration_records.append(record)
                _write_timing_record(timing_path, record)
                break

            env_step_total_ms = sum(record["env_step_ms"] for record in env_step_records)
            env_step_action_total_ms = env_step_total_ms
            post_step_observation_total_ms = sum(
                record.get("post_step_observation_total_ms") or 0.0
                for record in env_step_records
            )
            iteration_total_ms = _elapsed_ms(iteration_start)
            record = {
                "event": "iteration",
                "step": _step_i,
                "agent_step_ms": agent_step_ms,
                "agent_internal_ms": agent_internal,
                "env_step_total_ms": env_step_total_ms,
                "env_step_action_total_ms": env_step_action_total_ms,
                "post_step_observation_total_ms": post_step_observation_total_ms,
                "env_steps": env_step_records,
                "mark_done_step_ms": mark_done_step_ms,
                "iteration_total_ms": iteration_total_ms,
            }
            iteration_records.append(record)
            _write_timing_record(timing_path, record)
            llm_ms = (agent_internal or {}).get("llm_call_ms") if isinstance(agent_internal, dict) else None
            logger.info(
                "Step %d timing: total=%.2f ms agent=%.2f ms llm=%s env_step=%.2f ms action_groups=%d",
                _step_i,
                iteration_total_ms,
                agent_step_ms,
                f"{llm_ms:.2f} ms" if isinstance(llm_ms, (int, float)) else "n/a",
                env_step_total_ms,
                len(env_step_records),
            )

        episode_dir = env.episode_dir
        logger.info("Episode finished. See: %s info: %s", episode_dir, info)
    finally:
        if iteration_records and episode_dir:
            summary = _timing_summary(iteration_records)
            summary["event"] = "summary"
            summary["overall_ms"] = _elapsed_ms(overall_start)
            summary_path = Path(episode_dir) / "timing_summary.json"
            summary_path.write_text(json.dumps(summary, indent=2, default=str), encoding="utf-8")
            _write_timing_record(timing_path, summary)
            logger.info("Timing summary written to %s and %s", timing_path, summary_path)
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
