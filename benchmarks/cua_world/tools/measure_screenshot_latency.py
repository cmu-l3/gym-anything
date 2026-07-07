#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[3]
SRC_ROOT = REPO_ROOT / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from gym_anything import from_config  # noqa: E402


def _percentile(values: list[float], percentile: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, int(round((percentile / 100.0) * (len(ordered) - 1)))))
    return ordered[index]


def _summary(values: list[float]) -> dict[str, float]:
    return {
        "min_ms": min(values),
        "p50_ms": _percentile(values, 50),
        "p95_ms": _percentile(values, 95),
        "p99_ms": _percentile(values, 99),
        "max_ms": max(values),
        "mean_ms": sum(values) / len(values),
    }


def _capture_timed(env) -> tuple[float, Any]:
    start = time.perf_counter_ns()
    image = env.capture_screenshot_image()
    elapsed_ms = (time.perf_counter_ns() - start) / 1_000_000.0
    return elapsed_ms, image


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Measure real environment screenshot-object latency.")
    parser.add_argument(
        "--env-dir",
        default="benchmarks/cua_world/environments/google_earth_env",
        help="Environment directory to load.",
    )
    parser.add_argument(
        "--task",
        default="take_screenshot",
        help="Task id under the selected environment.",
    )
    parser.add_argument("--samples", type=int, default=50, help="Measured capture count.")
    parser.add_argument("--warmup", type=int, default=5, help="Warmup captures excluded from metrics.")
    parser.add_argument("--interleave", action="store_true", help="Alternate methods each sample round.")
    parser.add_argument(
        "--methods",
        default="qmp_ppm,qmp_png",
        help=(
            "Comma-separated capture methods to benchmark after one reset. "
            "Supported: qmp_ppm, qmp_ppm_direct, qmp_ppm_pil, qmp_png, legacy, "
            "api_capture_observation, api_step_noop, api_step_screenshot"
        ),
    )
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--use-cache", action="store_true")
    parser.add_argument("--cache-level", default="post_task", choices=["pre_start", "post_start", "post_task"])
    parser.add_argument("--use-savevm", action="store_true")
    parser.add_argument("--save-first", help="Optional path to save the first measured screenshot.")
    parser.add_argument("--output-json", help="Optional path to write the metrics JSON.")
    return parser


def _method_capture(env, method: str):
    runner = env._runner
    if method == "api_capture_observation":
        return env.capture_observation()["screen"]["image"]
    if method == "api_step_noop":
        obs, _, _, _ = env.step([])
        return obs["screen"]["image"]
    if method == "api_step_screenshot":
        obs, _, _, info = env.step([{"action": "screenshot"}])
        image = obs["screen"]["image"]
        if info.get("action_result", {}).get("output") is not image:
            raise RuntimeError("screenshot action did not return the observation image object")
        return image
    if method == "qmp_ppm":
        return runner._capture_screenshot_image_qmp("ppm", parser="pil")
    if method == "qmp_ppm_direct":
        return runner._capture_screenshot_image_qmp("ppm", parser="fast")
    if method == "qmp_ppm_pil":
        return runner._capture_screenshot_image_qmp("ppm", parser="pil")
    if method == "qmp_png":
        return runner._capture_screenshot_image_qmp("png")
    if method == "legacy":
        return runner._capture_screenshot_image_legacy()
    raise ValueError(f"Unknown method: {method}")


def _method_timed(env, method: str) -> tuple[float, Any]:
    start = time.perf_counter_ns()
    image = _method_capture(env, method)
    elapsed_ms = (time.perf_counter_ns() - start) / 1_000_000.0
    return elapsed_ms, image


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    methods = [item.strip() for item in args.methods.split(",") if item.strip()]
    env = from_config(args.env_dir, task_id=args.task, fast_io=True)
    timings: dict[str, Any] = {
        "env_dir": args.env_dir,
        "task": args.task,
        "samples": args.samples,
        "warmup": args.warmup,
        "methods": methods,
        "fast_io": True,
    }

    try:
        reset_start = time.perf_counter_ns()
        env.reset(
            seed=args.seed,
            use_cache=args.use_cache,
            cache_level=args.cache_level,
            use_savevm=args.use_savevm,
        )
        timings["reset_ms"] = (time.perf_counter_ns() - reset_start) / 1_000_000.0
        env.set_episode_limits(max_steps=None, timeout_sec=None)
        timings["runner_work_dir"] = str(getattr(env._runner, "_work_dir", ""))
        timings["runner_fast_io_dir"] = str(getattr(env._runner, "_fast_io_dir", "") or "")

        timings["capture_screenshot_image"] = {}
        saved_first = False
        if args.interleave:
            for _ in range(args.warmup):
                for method in methods:
                    _method_timed(env, method)
            method_samples: dict[str, list[float]] = {method: [] for method in methods}
            method_first_images: dict[str, Any] = {}
            for index in range(args.samples):
                round_methods = methods[index % len(methods):] + methods[:index % len(methods)]
                for method in round_methods:
                    elapsed_ms, image = _method_timed(env, method)
                    method_samples[method].append(elapsed_ms)
                    method_first_images.setdefault(method, image)
            for method in methods:
                first_image = method_first_images.get(method)
                method_result = _summary(method_samples[method])
                method_result["samples_ms"] = method_samples[method]
                if first_image is not None:
                    method_result["width"] = first_image.size[0]
                    method_result["height"] = first_image.size[1]
                timings["capture_screenshot_image"][method] = method_result
            if args.save_first and method_first_images:
                first_image = method_first_images[methods[0]]
                save_path = Path(args.save_first)
                save_path.parent.mkdir(parents=True, exist_ok=True)
                first_image.save(save_path)
                timings["saved_first"] = str(save_path)
        else:
            for method in methods:
                for _ in range(args.warmup):
                    _method_timed(env, method)

                samples: list[float] = []
                first_image = None
                for index in range(args.samples):
                    elapsed_ms, image = _method_timed(env, method)
                    samples.append(elapsed_ms)
                    if index == 0:
                        first_image = image

                method_result = _summary(samples)
                method_result["samples_ms"] = samples
                if first_image is not None:
                    method_result["width"] = first_image.size[0]
                    method_result["height"] = first_image.size[1]
                    if args.save_first and not saved_first:
                        save_path = Path(args.save_first)
                        save_path.parent.mkdir(parents=True, exist_ok=True)
                        first_image.save(save_path)
                        timings["saved_first"] = str(save_path)
                        saved_first = True
                timings["capture_screenshot_image"][method] = method_result
    finally:
        env._finalized = True
        env.close()

    print(json.dumps(timings, indent=2, sort_keys=True))
    if args.output_json:
        output_path = Path(args.output_json)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(timings, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
