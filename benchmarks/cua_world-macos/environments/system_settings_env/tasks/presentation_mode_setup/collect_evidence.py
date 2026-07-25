"""Comprehensive evidence collection for system_settings_env/presentation_mode_setup.

Mirrors `safari_env/tasks/devtools_security_header_audit/collect_evidence.py`
in shape, adapted for the System Settings target. Drives each flow through
the **gym-anything framework** (`from_config` → `env.reset` → `env.step` →
`env.step(mark_done=True)` → `env.close`), so the canonical authoritative
`summary.json` is produced by the framework and the artifact bundle
(`frame_00000.png`, `traj.jsonl`, `final.png`, `post_verification.png`) is
written to `<env>/artifacts/episode_*/`.

Usage:
    USE_COMPUTER_API_KEY=mk_live_… \\
    USE_COMPUTER_BASE_URL=https://api.dev.use.computer \\
    python3 collect_evidence.py [--flow do_nothing|wrong_target|happy_path|all]

Each flow opens a NEW use.computer sandbox (~30-45s reset), exercises a
specific completion path, and saves its artifacts under
`evidence_docs/presentation_mode_setup/<flow>/`. The `interactive_pilot/`
flow is built separately (see its README) because it requires real UI
driving via the visual_grounding MCP server.
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
EVIDENCE_ROOT = ENV_DIR / "evidence_docs" / "presentation_mode_setup"


def log(msg: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


# ---------------------------------------------------------------------------
# Helpers shared across flows
# ---------------------------------------------------------------------------

def _save_episode_artifacts(env, dest: Path) -> dict:
    """Copy the framework-written artifacts (summary.json, traj.jsonl, frame_*.png,
    final.png, post_verification.png) from the latest episode dir into our
    flow-specific evidence directory.
    """
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
    """copy_from helper that returns True/False and never raises."""
    try:
        env._runner.copy_from(remote_path, str(local_path))
        return local_path.exists() and local_path.stat().st_size > 0
    except Exception as exc:
        log(f"  copy_from {remote_path} failed: {exc}")
        return False


def _capture_logs(env, out_dir: Path) -> dict:
    """Pull the env / task hook logs from the sandbox (path uses
    /Users/lume/<name>.log on macOS, per 12_macos_environments.md).

    Only logs that exist at the time of the call are listed. `task_post_task.log`
    is intentionally excluded here because this helper runs PRE-finalize, before
    the framework triggers the post_task hook; the framework's own
    `_finalize_episode` writes that log into the episode artifacts dir, which
    `_save_episode_artifacts` copies into the flow dir.
    """
    logs = {}
    for name in ("env_setup_pre_start.log", "env_setup_post_start.log",
                 "task_pre_task.log"):
        remote = f"/Users/lume/{name}"
        local = out_dir / f"hook_log_{name}"
        copied = _save_remote(env, remote, local)
        tail = env._runner.exec_capture(f"tail -100 {remote} 2>/dev/null || echo NOT_FOUND").strip()
        logs[name] = {"copied": copied, "tail_100": tail}
    return logs


def _snapshot_defaults(env) -> dict:
    """Read all 5 target defaults values plus ShowAMPM. Used in evidence.json.

    Discard stderr (`2>/dev/null`) so absent keys produce empty strings,
    not the multi-line macOS "domain/default pair does not exist" diagnostic
    that `defaults` emits to stderr.
    """
    exec_capture = env._runner.exec_capture
    return {
        "AppleInterfaceStyle": exec_capture(
            "defaults read -g AppleInterfaceStyle 2>/dev/null"
        ).strip(),
        "dock.orientation": exec_capture(
            "defaults read com.apple.dock orientation 2>/dev/null"
        ).strip(),
        "dock.autohide": exec_capture(
            "defaults read com.apple.dock autohide 2>/dev/null"
        ).strip(),
        "dock.tilesize": exec_capture(
            "defaults read com.apple.dock tilesize 2>/dev/null"
        ).strip(),
        "clock.DateFormat": exec_capture(
            "defaults read com.apple.menuextra.clock DateFormat 2>/dev/null"
        ).strip(),
        "clock.ShowAMPM": exec_capture(
            "defaults read com.apple.menuextra.clock ShowAMPM 2>/dev/null"
        ).strip(),
    }


def _common_flow_setup(flow: str):
    """Create a fresh sandbox + env, reset, return env + evidence dir."""
    out_dir = ensure_dir(EVIDENCE_ROOT / flow)
    # Clear stale evidence to avoid mixing runs
    for f in out_dir.iterdir():
        if f.is_file():
            f.unlink()
        elif f.is_dir():
            shutil.rmtree(f)

    from gym_anything import from_config

    env = from_config(str(ENV_DIR), task_id="presentation_mode_setup")
    log(f"[{flow}] env loaded, runner={type(env._runner).__name__}")
    t0 = time.time()
    obs = env.reset(use_cache=False)
    log(f"[{flow}] reset took {time.time()-t0:.1f}s")
    return env, obs, out_dir


def _common_flow_finish(env, out_dir: Path, evidence: dict) -> dict:
    """Mark task done, read summary.json (authoritative), copy artifacts."""
    # A no-op mouse move is needed to satisfy step's "needs action" assumption.
    obs, reward, done, info = env.step(
        [{"mouse": {"move": [10, 10]}}], mark_done=True
    )
    # Brief settle so post_task + verifier finish + framework writes summary.json
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


# ---------------------------------------------------------------------------
# Flow: do_nothing — no agent action; verifier should refuse to score
# ---------------------------------------------------------------------------

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


# ---------------------------------------------------------------------------
# Flow: wrong_target — agent changed settings to non-target values.
# Strict gate should fire, score = 0.
# ---------------------------------------------------------------------------

def flow_wrong_target():
    env, obs, out_dir = _common_flow_setup("wrong_target")
    evidence = {"flow": "wrong_target", "started_at": time.strftime("%Y-%m-%dT%H:%M:%S")}

    env._runner.capture_screenshot(out_dir / "01_panel_view.png")

    log("[wrong_target] applying wrong-target changes: dock right + tilesize 96")
    env._runner.exec_capture(
        'defaults write com.apple.dock orientation -string "right"; '
        'defaults write com.apple.dock tilesize -int 96; '
        'killall Dock 2>/dev/null; '
        'killall cfprefsd 2>/dev/null; sleep 2'
    )
    env._runner.capture_screenshot(out_dir / "02_after_wrong_changes.png")

    evidence["defaults_after_wrong_changes"] = _snapshot_defaults(env)
    evidence["hook_logs_pre_finalize"] = _capture_logs(env, out_dir)

    env._runner.capture_screenshot(out_dir / "03_before_finalize.png")

    log("[wrong_target] mark_done…")
    evidence = _common_flow_finish(env, out_dir, evidence)

    (out_dir / "evidence.json").write_text(json.dumps(evidence, indent=2, default=str))
    log(f"[wrong_target] done; evidence in {out_dir}")
    return evidence


# ---------------------------------------------------------------------------
# Flow: happy_path — apply all 5 settings via Terminal `defaults write`.
# Should score 100/100. Uses the Terminal completion path which the task
# description explicitly allows ("you may use any means to apply these
# settings"). The interactive_pilot/ flow (separate) exercises the UI path.
# ---------------------------------------------------------------------------

def flow_happy_path():
    env, obs, out_dir = _common_flow_setup("happy_path")
    evidence = {"flow": "happy_path", "started_at": time.strftime("%Y-%m-%dT%H:%M:%S")}

    env._runner.capture_screenshot(out_dir / "01_panel_view.png")
    evidence["defaults_before_changes"] = _snapshot_defaults(env)

    log("[happy_path] applying all 5 settings via `defaults write` (Terminal path)")
    env._runner.exec_capture(
        'defaults write -g AppleInterfaceStyle -string "Dark"; '
        'defaults write com.apple.dock orientation -string "left"; '
        'defaults write com.apple.dock autohide -bool true; '
        'defaults write com.apple.dock tilesize -int 16; '
        'defaults write com.apple.menuextra.clock DateFormat -string "EEE MMM d  HH:mm"; '
        'killall cfprefsd 2>/dev/null; sleep 1; '
        'killall Dock 2>/dev/null; '
        'killall SystemUIServer 2>/dev/null; sleep 3'
    )
    env._runner.capture_screenshot(out_dir / "02_after_happy_changes.png")
    evidence["defaults_after_happy_changes"] = _snapshot_defaults(env)

    # Standalone run of export_result.sh to capture stdout/stderr of the
    # post_task hook independent of the framework's invocation.
    log("[happy_path] running export_result.sh standalone for stdout evidence")
    export_out = env._runner.exec_capture(
        "bash /Users/lume/workspace/tasks/presentation_mode_setup/export_result.sh 2>&1"
    )
    (out_dir / "export_script_output.txt").write_text(export_out)
    _save_remote(env, "/tmp/presentation_mode_setup_result.json",
                 out_dir / "export_result_json_standalone.json")

    env._runner.capture_screenshot(out_dir / "03_before_finalize.png")
    evidence["hook_logs_pre_finalize"] = _capture_logs(env, out_dir)

    log("[happy_path] mark_done…")
    evidence = _common_flow_finish(env, out_dir, evidence)

    # Also save the framework-run export result file for comparison.
    _save_remote(env, "/tmp/presentation_mode_setup_result.json",
                 out_dir / "export_result_json_framework.json")

    (out_dir / "evidence.json").write_text(json.dumps(evidence, indent=2, default=str))
    log(f"[happy_path] done; evidence in {out_dir}")
    return evidence


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--flow", default="all",
        choices=["all", "do_nothing", "wrong_target", "happy_path"],
    )
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
                "flow": flow,
                "ok": True,
                "score": verifier.get("score"),
                "passed": verifier.get("passed"),
            })
        except Exception as exc:
            log(f"FLOW {flow} FAILED: {exc}")
            import traceback; traceback.print_exc()
            summary["runs"].append({"flow": flow, "ok": False, "error": str(exc)})

    summary["finished_at"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    # Write to `_runs.json` rather than `_collection_summary.json`: the latter
    # is the curated human-authored top-level summary (includes interactive_pilot
    # info, MCP usage, live findings) and should not be clobbered by the
    # framework-only flows this script runs.
    (EVIDENCE_ROOT / "_runs.json").write_text(
        json.dumps(summary, indent=2, default=str)
    )
    log(f"All flows complete. Evidence root: {EVIDENCE_ROOT}")


if __name__ == "__main__":
    main()
