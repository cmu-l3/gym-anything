from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

from .api import from_config
from .compatibility import (
    get_runner_compatibility,
    get_runner_compatibility_matrix,
    render_compatibility_text,
)
from .doctor import render_doctor_text, render_doctor_rich, run_doctor
from .verification import (
    build_missing_hook_reference_manifest,
    build_task_status_manifest,
    build_verified_task_split,
    render_summary_text,
    verify_corpus,
    verify_environment_dir,
    write_json_report,
)
from .verification.pipeline import verify_task_pipeline
from .verification.reports import render_task_pipeline_result_text

_ENV_SEARCH_PATHS = [
    "benchmarks/cua_world/environments",
]


def _resolve_env_dir(name: str) -> str:
    """Resolve a short env name (e.g. 'moodle_env') to its full path."""
    # Already a valid path
    if Path(name).is_dir() and (Path(name) / "env.json").exists():
        return name
    # Search standard locations
    for base in _ENV_SEARCH_PATHS:
        candidate = Path(base) / name
        if candidate.is_dir() and (candidate / "env.json").exists():
            return str(candidate)
    # Fuzzy: try appending _env
    if not name.endswith("_env"):
        return _resolve_env_dir(name + "_env")
    print(f"Error: environment '{name}' not found.", file=sys.stderr)
    print(f"Run 'gym-anything list' to see available environments.", file=sys.stderr)
    sys.exit(1)


def _print_json(data) -> None:
    print(json.dumps(data, indent=2, sort_keys=True))


def cmd_verify_spec(args):
    args.env_dir = _resolve_env_dir(args.env_dir)
    summary = verify_environment_dir(args.env_dir, task_id=args.task)
    if args.json:
        _print_json(summary.to_dict())
    else:
        print(render_summary_text(summary))
    return 0 if summary.ok else 1


def cmd_verify_corpus(args):
    summary = verify_corpus(args.root, max_failures=args.max_failures)
    if args.write_status_manifest:
        write_json_report(build_task_status_manifest(summary), args.write_status_manifest)
    if args.write_verified_split:
        write_json_report(build_verified_task_split(summary), args.write_verified_split)
    if args.write_missing_hook_manifest:
        write_json_report(build_missing_hook_reference_manifest(summary), args.write_missing_hook_manifest)
    if args.json:
        _print_json(summary.to_dict())
    else:
        print(render_summary_text(summary))
    return 0 if summary.ok else 1


def cmd_verify_task(args):
    args.env_dir = _resolve_env_dir(args.env_dir)
    result = verify_task_pipeline(
        env_dir=args.env_dir,
        task_id=args.task,
        seed=args.seed,
        use_cache=args.use_cache,
        cache_level=args.cache_level,
        use_savevm=args.use_savevm,
    )
    if args.json:
        _print_json(result.to_dict())
    else:
        print(render_task_pipeline_result_text(result))
    return 0 if result.ok else 1


def cmd_validate(args):
    args.env_dir = _resolve_env_dir(args.env_dir)
    summary = verify_environment_dir(args.env_dir, task_id=args.task)
    if summary.ok:
        first_task = next((record.spec_id for record in summary.records if record.kind == "task"), None)
        env_id = next((record.spec_id for record in summary.records if record.kind == "env"), None)
        print("Spec OK:", env_id, "task=", first_task)
        return 0
    print(render_summary_text(summary), file=sys.stderr)
    return 1


def _pick_random_task(env_dir: str) -> str:
    """Pick a random task from the environment's tasks directory."""
    import random
    tasks_dir = Path(env_dir) / "tasks"
    if not tasks_dir.is_dir():
        return None
    tasks = [t.name for t in tasks_dir.iterdir() if t.is_dir()]
    if not tasks:
        return None
    chosen = random.choice(tasks)
    return chosen


def cmd_run(args):
    args.env_dir = _resolve_env_dir(args.env_dir)
    if not args.task:
        args.task = _pick_random_task(args.env_dir)
        if args.task:
            print(f"No task specified, randomly selected: {args.task}")
    env = from_config(args.env_dir, task_id=args.task)

    if args.interactive:
        from .tui.progress import create_reporter
        from .tui.session import InteractiveSession

        env_name = Path(args.env_dir).name
        reporter = create_reporter(env_name=env_name, task_name=args.task or "")
        env.set_reporter(reporter)

        reporter.define_stages([
            ("instance", "Initializing instance"),
            ("base_image", "Base image check"),
            ("cow_overlay", "COW overlay"),
            ("networking", "Network setup"),
            ("vm_launch", "Launching VM"),
            ("port_forward", "Port forwarding"),
            ("ssh_wait", "Waiting for SSH"),
            ("rosetta", "Rosetta setup"),
            ("desktop_wait", "Waiting for desktop"),
            ("vnc_setup", "VNC setup"),
            ("mounts", "File mounts"),
            ("pre_start_hook", "Pre-start hook"),
            ("post_start_hook", "Post-start hook"),
            ("pre_task_hook", "Pre-task hook"),
            ("ready", "Ready"),
        ])

        with reporter:
            obs = env.reset(seed=args.seed)

        session = InteractiveSession(env, auto_open_vnc=getattr(args, "open_vnc", False))
        session.run()
        return 0

    # Non-interactive mode: run steps
    obs = env.reset(seed=args.seed)
    print("Episode started. Artifacts will be saved under:", env.episode_dir)
    steps = args.steps or (env.task_spec.init.max_steps if env.task_spec else 10)
    for i in range(steps):
        if i == 9:
            if args.debug:
                breakpoint()
        obs, reward, done, info = env.step({})
        if done:
            break
        time.sleep(0.2)
    if args.debug:
        breakpoint()
    episode_dir = env.episode_dir
    env.close()
    print("Episode finished. See:", episode_dir)
    return 0


def cmd_compatibility(args):
    if args.runner:
        compatibilities = [get_runner_compatibility(args.runner)]
    else:
        compatibilities = get_runner_compatibility_matrix()
    if args.json:
        _print_json([item.to_dict() for item in compatibilities])
    else:
        print(render_compatibility_text(compatibilities))
    return 0


def cmd_list(args):
    for base in _ENV_SEARCH_PATHS:
        base_path = Path(base)
        if not base_path.is_dir():
            continue
        envs = sorted(
            d.name for d in base_path.iterdir()
            if d.is_dir() and (d / "env.json").exists()
        )
        if not envs:
            continue
        for env_name in envs:
            env_dir = base_path / env_name
            tasks = sorted(
                t.name for t in (env_dir / "tasks").iterdir()
                if t.is_dir()
            ) if (env_dir / "tasks").is_dir() else []
            if args.verbose:
                print(f"{env_name}  ({len(tasks)} tasks)")
                for t in tasks:
                    print(f"  - {t}")
            else:
                task_str = f"  ({len(tasks)} tasks)" if tasks else ""
                print(f"{env_name}{task_str}")
    return 0


def cmd_doctor(args):
    report = run_doctor(
        runner=args.runner,
        verification_root=Path(args.verification_root) if args.verification_root else None,
    )
    if args.json:
        _print_json(report.to_dict())
    else:
        # Show the rich platform-aware output first
        print(render_doctor_rich(report))
        print()
        # Then the per-check details
        print(render_doctor_text(report))
    return 0 if report.ok else 1


def main(argv=None):
    parser = argparse.ArgumentParser(prog="gym-anything")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_verify = sub.add_parser("verify", help="Run verification checks")
    verify_sub = p_verify.add_subparsers(dest="verify_cmd", required=True)

    p_verify_spec = verify_sub.add_parser("spec", help="Verify one environment and its task specs")
    p_verify_spec.add_argument("env_dir")
    p_verify_spec.add_argument("--task")
    p_verify_spec.add_argument("--json", action="store_true")
    p_verify_spec.set_defaults(func=cmd_verify_spec)

    p_verify_corpus = verify_sub.add_parser("corpus", help="Verify all environment and task specs under a root")
    p_verify_corpus.add_argument("root", nargs="?", default="benchmarks/cua_world/environments")
    p_verify_corpus.add_argument("--max-failures", type=int)
    p_verify_corpus.add_argument("--write-status-manifest")
    p_verify_corpus.add_argument("--write-verified-split")
    p_verify_corpus.add_argument("--write-missing-hook-manifest")
    p_verify_corpus.add_argument("--json", action="store_true")
    p_verify_corpus.set_defaults(func=cmd_verify_corpus)

    p_verify_task = verify_sub.add_parser("task", help="Run a task through reset/finalize and execute its verifier")
    p_verify_task.add_argument("env_dir")
    p_verify_task.add_argument("--task", required=True)
    p_verify_task.add_argument("--seed", type=int, default=42)
    p_verify_task.add_argument("--use_cache", action="store_true")
    p_verify_task.add_argument("--cache_level", default="pre_start")
    p_verify_task.add_argument("--use_savevm", action="store_true")
    p_verify_task.add_argument("--json", action="store_true")
    p_verify_task.set_defaults(func=cmd_verify_task)

    p_val = sub.add_parser("validate", help="Validate env/task specs")
    p_val.add_argument("env_dir")
    p_val.add_argument("--task")
    p_val.set_defaults(func=cmd_validate)

    p_list = sub.add_parser("list", help="List available environments")
    p_list.add_argument("-v", "--verbose", action="store_true", help="Show tasks for each environment")
    p_list.set_defaults(func=cmd_list)

    p_run = sub.add_parser("run", help="Run an environment")
    p_run.add_argument("env_dir", help="Environment name (e.g. moodle_env) or path")
    p_run.add_argument("--task", help="Task ID to load")
    p_run.add_argument("--interactive", "-i", action="store_true",
                       help="Keep environment alive for interactive use (VNC/SSH). Press Ctrl+C to stop.")
    p_run.add_argument("--steps", type=int, help="Number of steps to run (non-interactive mode)")
    p_run.add_argument("--seed", type=int, default=42)
    p_run.add_argument("--debug", action="store_true")
    p_run.add_argument("--open-vnc", action="store_true",
                       help="Automatically open VNC viewer after boot (macOS: Screen Sharing)")
    p_run.set_defaults(func=cmd_run)

    p_compat = sub.add_parser("compatibility", help="Show the runner compatibility checklist")
    p_compat.add_argument("--runner", choices=["docker", "qemu", "qemu_native", "avd", "avd_native", "avf", "apptainer", "local"])
    p_compat.add_argument("--json", action="store_true")
    p_compat.set_defaults(func=cmd_compatibility)

    p_doctor = sub.add_parser("doctor", help="Check system prerequisites and optional verifier imports")
    p_doctor.add_argument("--runner", choices=["docker", "qemu", "qemu_native", "avd", "avd_native", "avf", "apptainer", "local"])
    p_doctor.add_argument("--verification-root")
    p_doctor.add_argument("--json", action="store_true")
    p_doctor.set_defaults(func=cmd_doctor)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
