"""Evidence collection for system_settings_env/family_accessibility_elderly.

Usage:
    USE_COMPUTER_API_KEY=mk_live_… \\
    USE_COMPUTER_BASE_URL=https://api.dev.use.computer \\
    python3 collect_evidence.py [--flow do_nothing|wrong_target|happy_path|all]
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[6]
ENV_DIR = REPO_ROOT / "benchmarks" / "cua_world-macos" / "environments" / "system_settings_env"
TASK_NAME = "family_accessibility_elderly"
EVIDENCE_ROOT = ENV_DIR / "evidence_docs" / TASK_NAME


def log(msg: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def _save_episode_artifacts(env, dest: Path) -> dict:
    artifacts_root = ENV_DIR / "artifacts"
    if not artifacts_root.exists():
        return {"saved": False, "reason": "no artifacts root"}
    episodes = sorted([d for d in artifacts_root.iterdir() if d.name.startswith("episode_")])
    if not episodes:
        return {"saved": False, "reason": "no episode dirs"}
    latest = episodes[-1]
    saved_files = []
    for src in latest.iterdir():
        dst = dest / src.name
        try:
            if src.is_file():
                shutil.copy(src, dst)
                saved_files.append(src.name)
            elif src.is_dir():
                shutil.copytree(src, dst, dirs_exist_ok=True)
                saved_files.append(src.name + "/")
        except Exception as exc:
            log(f"  copy {src.name} failed: {exc}")
    return {"saved": True, "episode_dir": str(latest.name), "files": saved_files}


def _save_remote(env, remote_path: str, local_path: Path) -> bool:
    try:
        env._runner.copy_from(remote_path, str(local_path))
        return local_path.exists() and local_path.stat().st_size > 0
    except Exception as exc:
        log(f"  copy_from {remote_path} failed: {exc}")
        return False


def _capture_logs(env, out_dir: Path) -> dict:
    logs = {}
    for name in ("env_setup_pre_start.log", "env_setup_post_start.log", "task_pre_task.log"):
        remote = f"/Users/lume/{name}"
        local = out_dir / f"hook_log_{name}"
        copied = _save_remote(env, remote, local)
        tail = env._runner.exec_capture(f"tail -100 {remote} 2>/dev/null || echo NOT_FOUND").strip()
        logs[name] = {"copied": copied, "tail_100": tail}
    return logs


def _snapshot_defaults(env) -> dict:
    exec_capture = env._runner.exec_capture
    return {
        "increaseContrast": exec_capture(
            "defaults read com.apple.universalaccess increaseContrast 2>/dev/null"
        ).strip(),
        "reduceTransparency": exec_capture(
            "defaults read com.apple.universalaccess reduceTransparency 2>/dev/null"
        ).strip(),
        "cursorSize": exec_capture(
            "defaults read com.apple.universalaccess cursorSize 2>/dev/null"
        ).strip(),
        "closeViewScrollWheelToggle": exec_capture(
            "defaults read com.apple.universalaccess closeViewScrollWheelToggle 2>/dev/null"
        ).strip(),
        "stickyKey": exec_capture(
            "defaults read com.apple.universalaccess stickyKey 2>/dev/null"
        ).strip(),
        "slowKey": exec_capture(
            "defaults read com.apple.universalaccess slowKey 2>/dev/null"
        ).strip(),
    }


def _common_flow_setup(flow: str):
    out_dir = ensure_dir(EVIDENCE_ROOT / flow)
    for f in out_dir.iterdir():
        if f.is_file():
            f.unlink()
        elif f.is_dir():
            shutil.rmtree(f)
    from gym_anything import from_config
    env = from_config(str(ENV_DIR), task_id=TASK_NAME)
    log(f"[{flow}] env loaded, runner={type(env._runner).__name__}")
    t0 = time.time()
    obs = env.reset(use_cache=False)
    log(f"[{flow}] reset took {time.time()-t0:.1f}s")
    return env, obs, out_dir


def _common_flow_finish(env, out_dir: Path, evidence: dict) -> dict:
    obs, reward, done, info = env.step([{"mouse": {"move": [10, 10]}}], mark_done=True)
    time.sleep(5)
    artifact_info = _save_episode_artifacts(env, out_dir)
    evidence["framework_artifacts"] = artifact_info
    summary_path = out_dir / "summary.json"
    if summary_path.exists():
        with open(summary_path) as f:
            summary = json.load(f)
        evidence["verifier_summary_json"] = summary.get("verifier", {})
    else:
        evidence["verifier_summary_json"] = None
        evidence["verifier_info_dict_fallback"] = info.get("verifier")
    evidence["final_reward"] = reward
    evidence["final_done"] = done
    env.close()
    return evidence


def flow_do_nothing():
    env, obs, out_dir = _common_flow_setup("do_nothing")
    evidence = {"flow": "do_nothing", "started_at": time.strftime("%Y-%m-%dT%H:%M:%S")}
    env._runner.capture_screenshot(out_dir / "01_panel_view.png")
    evidence["defaults_after_setup"] = _snapshot_defaults(env)
    evidence["system_settings_process"] = env._runner.exec_capture(
        "pgrep -x 'System Settings' || echo NONE"
    ).strip()
    evidence["hook_logs_pre_finalize"] = _capture_logs(env, out_dir)
    env._runner.capture_screenshot(out_dir / "02_before_finalize.png")
    log("[do_nothing] mark_done…")
    evidence = _common_flow_finish(env, out_dir, evidence)
    (out_dir / "evidence.json").write_text(json.dumps(evidence, indent=2, default=str))
    log(f"[do_nothing] done; evidence in {out_dir}")
    return evidence


def flow_wrong_target():
    env, obs, out_dir = _common_flow_setup("wrong_target")
    evidence = {"flow": "wrong_target", "started_at": time.strftime("%Y-%m-%dT%H:%M:%S")}
    env._runner.capture_screenshot(out_dir / "01_panel_view.png")
    log("[wrong_target] applying wrong-target: cursor=2.0 only (partial, no full-credit)")
    env._runner.exec_capture(
        "defaults write com.apple.universalaccess cursorSize -float 2.0; "
        "killall cfprefsd 2>/dev/null; sleep 1"
    )
    env._runner.capture_screenshot(out_dir / "02_after_wrong_changes.png")
    evidence["defaults_after_wrong"] = _snapshot_defaults(env)
    evidence["hook_logs_pre_finalize"] = _capture_logs(env, out_dir)
    log("[wrong_target] mark_done…")
    evidence = _common_flow_finish(env, out_dir, evidence)
    (out_dir / "evidence.json").write_text(json.dumps(evidence, indent=2, default=str))
    log(f"[wrong_target] done; evidence in {out_dir}")
    return evidence


def flow_happy_path():
    env, obs, out_dir = _common_flow_setup("happy_path")
    evidence = {"flow": "happy_path", "started_at": time.strftime("%Y-%m-%dT%H:%M:%S")}
    env._runner.capture_screenshot(out_dir / "01_panel_view.png")
    evidence["defaults_before"] = _snapshot_defaults(env)
    log("[happy_path] applying all 6 accessibility settings via defaults write")
    env._runner.exec_capture(
        "defaults write com.apple.universalaccess increaseContrast -bool true; "
        "defaults write com.apple.universalaccess reduceTransparency -bool true; "
        "defaults write com.apple.universalaccess cursorSize -float 3.5; "
        "defaults write com.apple.universalaccess closeViewScrollWheelToggle -bool true; "
        "defaults write com.apple.universalaccess stickyKey -bool true; "
        "defaults write com.apple.universalaccess slowKey -bool true; "
        "killall cfprefsd 2>/dev/null; sleep 2"
    )
    env._runner.capture_screenshot(out_dir / "02_after_changes.png")
    evidence["defaults_after"] = _snapshot_defaults(env)
    export_out = env._runner.exec_capture(
        f"bash /Users/lume/workspace/tasks/{TASK_NAME}/export_result.sh 2>&1"
    )
    (out_dir / "export_script_output.txt").write_text(export_out)
    _save_remote(env, f"/tmp/{TASK_NAME}_result.json", out_dir / "export_result_json.json")
    env._runner.capture_screenshot(out_dir / "03_before_finalize.png")
    evidence["hook_logs_pre_finalize"] = _capture_logs(env, out_dir)
    log("[happy_path] mark_done…")
    evidence = _common_flow_finish(env, out_dir, evidence)
    (out_dir / "evidence.json").write_text(json.dumps(evidence, indent=2, default=str))
    log(f"[happy_path] done; evidence in {out_dir}")
    return evidence


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--flow", default="all",
                        choices=["all", "do_nothing", "wrong_target", "happy_path"])
    args = parser.parse_args()
    if not os.environ.get("USE_COMPUTER_API_KEY"):
        sys.exit("USE_COMPUTER_API_KEY must be set")
    if not os.environ.get("USE_COMPUTER_BASE_URL"):
        os.environ["USE_COMPUTER_BASE_URL"] = "https://api.use.computer"
    import logging
    logging.basicConfig(level=logging.WARNING,
                        format="%(asctime)s %(name)s %(levelname)s %(message)s")
    ensure_dir(EVIDENCE_ROOT)
    summary = {"runs": [], "started_at": time.strftime("%Y-%m-%dT%H:%M:%S")}
    flows = ["do_nothing", "wrong_target", "happy_path"] if args.flow == "all" else [args.flow]
    for flow in flows:
        log(f"=== starting flow: {flow} ===")
        try:
            if flow == "do_nothing":
                result = flow_do_nothing()
            elif flow == "wrong_target":
                result = flow_wrong_target()
            elif flow == "happy_path":
                result = flow_happy_path()
            verifier = (result or {}).get("verifier_summary_json") or {}
            summary["runs"].append({
                "flow": flow, "ok": True,
                "score": verifier.get("score"), "passed": verifier.get("passed"),
            })
        except Exception as exc:
            log(f"FLOW {flow} FAILED: {exc}")
            import traceback; traceback.print_exc()
            summary["runs"].append({"flow": flow, "ok": False, "error": str(exc)})
    summary["finished_at"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    (EVIDENCE_ROOT / "_runs.json").write_text(json.dumps(summary, indent=2, default=str))
    log(f"All flows complete. Evidence root: {EVIDENCE_ROOT}")


if __name__ == "__main__":
    main()
