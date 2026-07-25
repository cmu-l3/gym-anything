"""Live-run evidence collection for raycast_env tasks.

Runs each of the 5 new Raycast tasks against a fresh use.computer sandbox,
captures screenshots + setup artifacts, does a do-nothing finish, and saves
everything under evidence_docs/<task_name>/.

Usage:
    USE_COMPUTER_API_KEY=mk_live_... \\
    USE_COMPUTER_BASE_URL=https://api.dev.use.computer \\
    python3 collect_evidence.py [--task all|<task_name>]

Evidence is written to:
  benchmarks/cua_world-macos/environments/raycast_env/evidence_docs/<task>/
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[4]
ENV_DIR = REPO_ROOT / "benchmarks" / "cua_world-macos" / "environments" / "raycast_env"
EVIDENCE_ROOT = ENV_DIR / "evidence_docs"

TASKS = [
    "raycast_workspace_orchestrator",
    "raycast_window_layout_reading",
    "raycast_quicklinks_dynamic",
    "raycast_clipboard_pipeline",
    "raycast_snippet_placeholders_live",
]


def log(msg: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def _save_remote(env, remote_path: str, local_path: Path) -> bool:
    try:
        env._runner.copy_from(remote_path, str(local_path))
        return local_path.exists() and local_path.stat().st_size > 0
    except Exception as exc:
        log(f"  copy_from {remote_path} failed: {exc}")
        return False


def _save_episode_artifacts(env, out_dir: Path) -> dict:
    """Copy latest episode artifacts directory into out_dir."""
    try:
        artifacts_base = Path(env._runner.artifacts_dir)
    except AttributeError:
        return {"saved": False, "reason": "no artifacts_dir on runner"}

    episodes = sorted(artifacts_base.iterdir(), key=lambda p: p.stat().st_mtime)
    if not episodes:
        return {"saved": False, "reason": "no episode dirs found"}
    latest = episodes[-1]
    saved_files = []
    for src in latest.iterdir():
        dst = out_dir / src.name
        try:
            shutil.copy(src, dst)
            saved_files.append(src.name)
        except Exception as exc:
            log(f"  copy {src.name} failed: {exc}")
    return {"saved": True, "episode_dir": str(latest.name), "files": saved_files}


def _capture_hook_logs(env, out_dir: Path) -> dict:
    logs = {}
    for name in ("env_setup_pre_start.log", "env_setup_post_start.log",
                 "task_pre_task.log", "task_post_task.log"):
        remote = f"/Users/lume/{name}"
        local = out_dir / f"hook_log_{name}"
        copied = _save_remote(env, remote, local)
        tail = env._runner.exec_capture(f"tail -100 {remote} 2>&1 || echo NOT_FOUND").strip()
        logs[name] = {"copied": copied, "tail_100": tail}
    return logs


def run_task(task_name: str) -> dict:
    from gym_anything import from_config

    out_dir = ensure_dir(EVIDENCE_ROOT / task_name)
    # Clear stale evidence
    for f in out_dir.iterdir():
        if f.is_file():
            f.unlink()
        elif f.is_dir():
            shutil.rmtree(f)

    evidence: dict = {
        "task": task_name,
        "started_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
    }

    log(f"[{task_name}] loading env...")
    env = from_config(str(ENV_DIR), task_id=task_name)
    log(f"[{task_name}] runner={type(env._runner).__name__}")

    t0 = time.time()
    obs = env.reset(use_cache=False)
    log(f"[{task_name}] reset in {time.time()-t0:.1f}s")

    # --- Screenshot after setup ---
    env._runner.capture_screenshot(out_dir / "01_after_setup.png")
    log(f"[{task_name}] 01_after_setup.png saved")

    # --- Probe: check that setup files exist ---
    ts_file = f"/tmp/{task_name}_start_ts"
    evidence["start_ts_file"] = env._runner.exec_capture(
        f"ls -la {ts_file} 2>&1"
    ).strip()
    evidence["start_ts_value"] = env._runner.exec_capture(
        f"cat {ts_file} 2>/dev/null || echo MISSING"
    ).strip()

    # Task-specific setup checks
    if task_name == "raycast_workspace_orchestrator":
        evidence["script_dir"] = env._runner.exec_capture(
            "ls ~/Library/Application\\ Support/com.raycast.macos/script-commands/ 2>&1 | head -20"
        ).strip()
        evidence["running_apps"] = env._runner.exec_capture(
            "pgrep -fl 'Safari|Notes|TextEdit' 2>&1"
        ).strip()

    elif task_name == "raycast_window_layout_reading":
        evidence["running_apps"] = env._runner.exec_capture(
            "pgrep -fl 'Safari|Notes' 2>&1"
        ).strip()

    elif task_name == "raycast_quicklinks_dynamic":
        evidence["stale_export"] = env._runner.exec_capture(
            "ls -la ~/Desktop/my_quicklinks.json 2>&1"
        ).strip()

    elif task_name == "raycast_clipboard_pipeline":
        evidence["stale_files"] = env._runner.exec_capture(
            "ls -la ~/Desktop/clipboard_test.txt ~/Desktop/snippets.raycastsnippets 2>&1"
        ).strip()

    elif task_name == "raycast_snippet_placeholders_live":
        evidence["today_file"] = env._runner.exec_capture(
            f"cat /tmp/{task_name}_today 2>/dev/null || echo MISSING"
        ).strip()
        evidence["stale_files"] = env._runner.exec_capture(
            "ls -la ~/Desktop/snippet_test.txt ~/Desktop/snippets_live.raycastsnippets 2>&1"
        ).strip()

    # --- Hook logs before finalize ---
    evidence["hook_logs"] = _capture_hook_logs(env, out_dir)

    # --- Pre-finalize screenshot ---
    env._runner.capture_screenshot(out_dir / "02_before_finalize.png")
    log(f"[{task_name}] 02_before_finalize.png saved")

    # --- Do-nothing finish ---
    log(f"[{task_name}] marking done (no agent actions)...")
    obs2, reward, done, info = env.step([], mark_done=True)
    time.sleep(5)

    evidence["reward"] = reward
    evidence["done"] = done
    evidence["verifier"] = info.get("verifier") or info.get("verifier_result")

    # --- Artifacts ---
    artifact_info = _save_episode_artifacts(env, out_dir)
    evidence["framework_artifacts"] = artifact_info
    summary_path = out_dir / "summary.json"
    if summary_path.exists():
        with open(summary_path) as f:
            evidence["summary_json"] = json.load(f)

    env.close()

    (out_dir / "evidence.json").write_text(json.dumps(evidence, indent=2, default=str))
    log(f"[{task_name}] done — reward={reward} verifier={evidence['verifier']}")
    log(f"[{task_name}] evidence at {out_dir}")
    return evidence


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--task", default="all",
                        help=f"Task name or 'all'. Tasks: {', '.join(TASKS)}")
    args = parser.parse_args()

    sys.path.insert(0, str(REPO_ROOT / "src"))

    if args.task == "all":
        targets = TASKS
    elif args.task in TASKS:
        targets = [args.task]
    else:
        print(f"Unknown task '{args.task}'. Valid: {TASKS}")
        sys.exit(1)

    results = {}
    for task in targets:
        log(f"\n{'='*60}")
        log(f"Starting task: {task}")
        log(f"{'='*60}")
        try:
            ev = run_task(task)
            results[task] = {"status": "ok", "reward": ev.get("reward"), "verifier": ev.get("verifier")}
        except Exception as exc:
            log(f"[{task}] FAILED: {exc}")
            import traceback
            traceback.print_exc()
            results[task] = {"status": "error", "error": str(exc)}

    log("\n" + "="*60)
    log("SUMMARY")
    log("="*60)
    for task, r in results.items():
        log(f"  {task}: {r}")


if __name__ == "__main__":
    main()
