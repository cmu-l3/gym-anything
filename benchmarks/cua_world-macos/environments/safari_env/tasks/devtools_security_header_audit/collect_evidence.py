"""Comprehensive evidence collection for safari_env/devtools_security_header_audit.

Run one or more flows against a fresh use.computer sandbox; capture every
artifact required by 04_evidence_documentation.md plus a couple of probes
(Safari preference application variants, per-site navigation screenshots).

Usage:
    USE_COMPUTER_API_KEY=mk_live_… \\
    USE_COMPUTER_BASE_URL=https://api.dev.use.computer \\
    python3 collect_evidence.py [--flow probe_prefs|do_nothing|wrong_target|happy_path|all]

Each flow opens a NEW sandbox (~30-45s reset), exercises a specific path, and
saves its artifacts under:
  benchmarks/cua_world-macos/environments/safari_env/evidence_docs/
    devtools_security_header_audit/<flow>/
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
ENV_DIR = REPO_ROOT / "benchmarks" / "cua_world-macos" / "environments" / "safari_env"
EVIDENCE_ROOT = ENV_DIR / "evidence_docs" / "devtools_security_header_audit"


def log(msg: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


# ---------------------------------------------------------------------------
# Probe: which Safari pref-application variant actually enables the
# Develop menu and Bookmarks bar?
# ---------------------------------------------------------------------------

def flow_probe_prefs(Computer):
    """Try several `defaults write` variants for IncludeDevelopMenu /
    ShowFavoritesBar and screenshot Safari's menu bar after each launch."""
    out_dir = ensure_dir(EVIDENCE_ROOT / "probe_prefs")
    findings = {}
    variants = [
        ("A_current",
         "defaults write com.apple.Safari IncludeDevelopMenu -bool true; "
         "defaults write com.apple.Safari ShowFavoritesBar -bool true; "
         "killall cfprefsd"),
        ("B_app_flag",
         # `defaults write -app Safari` uses CFPreferencesAppValueSet under
         # the hood, which writes to the right host-scoped plist.
         "defaults write -app Safari IncludeDevelopMenu -bool true; "
         "defaults write -app Safari ShowFavoritesBar -bool true; "
         "killall cfprefsd"),
        ("C_plistbuddy",
         "/usr/libexec/PlistBuddy -c 'Set :IncludeDevelopMenu true' "
         "  ~/Library/Preferences/com.apple.Safari.plist 2>/dev/null || "
         "/usr/libexec/PlistBuddy -c 'Add :IncludeDevelopMenu bool true' "
         "  ~/Library/Preferences/com.apple.Safari.plist; "
         "/usr/libexec/PlistBuddy -c 'Set :ShowFavoritesBar true' "
         "  ~/Library/Preferences/com.apple.Safari.plist 2>/dev/null || "
         "/usr/libexec/PlistBuddy -c 'Add :ShowFavoritesBar bool true' "
         "  ~/Library/Preferences/com.apple.Safari.plist; "
         "killall cfprefsd"),
        ("D_killcfprefsd_first",
         "killall cfprefsd; sleep 1; "
         "defaults write com.apple.Safari IncludeDevelopMenu -bool true; "
         "defaults write com.apple.Safari ShowFavoritesBar -bool true"),
    ]

    for name, cmd in variants:
        log(f"probe variant {name}")
        cc = Computer(base_url=os.environ["USE_COMPUTER_BASE_URL"])
        with cc.create() as mac:
            mac.start_keepalive(interval=30)
            # Apply the variant
            mac.exec_ssh(cmd, timeout=30)
            # Confirm what defaults read sees
            read_out = mac.exec_ssh(
                "defaults read com.apple.Safari IncludeDevelopMenu 2>&1; "
                "defaults read com.apple.Safari ShowFavoritesBar 2>&1",
                timeout=10,
            ).stdout
            # Launch Safari
            mac.exec_ssh("open -a Safari", timeout=10)
            # Wait for window
            for _ in range(20):
                ls = mac.exec_ssh("/usr/bin/lsappinfo list | grep -iE 'Safari( |$)' || true", timeout=5).stdout
                if ls.strip():
                    break
                time.sleep(1)
            time.sleep(4)   # let menu bar render
            png = mac.screenshot.take_full_screen()
            shot = out_dir / f"{name}.png"
            shot.write_bytes(png)
            findings[name] = {"defaults_read": read_out, "screenshot": str(shot.relative_to(REPO_ROOT))}
        cc.close()

    (out_dir / "findings.json").write_text(json.dumps(findings, indent=2))
    log(f"probe_prefs done — {len(variants)} screenshots in {out_dir}")
    return findings


# ---------------------------------------------------------------------------
# Helper used by the three task-flow runs: spin up env via the real API path,
# capture per-step evidence, finalize, copy episode artifacts.
# ---------------------------------------------------------------------------

def _save_episode_artifacts(env, dest: Path) -> dict:
    """Copy the framework-written artifacts (summary.json, traj.jsonl, frames)
    from the latest episode dir into our flow-specific evidence directory.
    Returns a small dict describing what was saved."""
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
            shutil.copy(src, dst)
            saved_files.append(src.name)
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
    """Pull the Safari/env hook logs explicitly (the framework's diagnostics
    block copies them too, but only if diagnostics: true is set AND copy_from
    can find them). We capture both via copy_from AND via exec_capture tail
    so we have a reliable record either way."""
    logs = {}
    for name in ("env_setup_pre_start.log", "env_setup_post_start.log",
                 "task_pre_task.log", "task_post_task.log"):
        remote = f"/Users/lume/{name}"
        # First: try copy_from to grab the whole file
        local = out_dir / f"hook_log_{name}"
        copied = _save_remote(env, remote, local)
        # Fallback: tail via exec_capture, embed in our log dict
        tail = env._runner.exec_capture(f"tail -100 {remote} 2>&1 || echo NOT_FOUND").strip()
        logs[name] = {"copied": copied, "tail_100": tail}
    return logs


def _common_flow_setup(Computer, flow: str):
    """Create a fresh sandbox, env, evidence dir; run env.reset(); return everything."""
    out_dir = ensure_dir(EVIDENCE_ROOT / flow)
    # Clear stale evidence to avoid mixing runs
    for f in out_dir.iterdir():
        if f.is_file():
            f.unlink()
        elif f.is_dir():
            shutil.rmtree(f)

    from gym_anything import from_config

    env = from_config(str(ENV_DIR), task_id="devtools_security_header_audit")
    log(f"[{flow}] env loaded, runner={type(env._runner).__name__}")
    t0 = time.time()
    obs = env.reset(use_cache=False)
    log(f"[{flow}] reset took {time.time()-t0:.1f}s")
    return env, obs, out_dir


def _common_flow_finish(env, out_dir: Path, evidence: dict) -> dict:
    """Mark task done, read summary.json (authoritative), copy artifacts."""
    obs, reward, done, info = env.step([{"mouse": {"move": [10, 10]}}], mark_done=True)
    # Brief settle so post_task + verifier finish + framework writes summary.json
    time.sleep(5)
    # Read summary.json (authoritative per 04_evidence_documentation.md)
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

def flow_do_nothing(Computer):
    from gym_anything import from_config  # noqa: F401 — ensure import ok
    env, obs, out_dir = _common_flow_setup(Computer, "do_nothing")
    evidence = {"flow": "do_nothing", "started_at": time.strftime("%Y-%m-%dT%H:%M:%S")}

    # Save panel-view (what the interactive viewer would see at task start)
    env._runner.capture_screenshot(out_dir / "01_panel_view.png")

    # Read env-level prefs to record actual Safari state
    evidence["safari_prefs_after_setup"] = {
        "IncludeDevelopMenu": env._runner.exec_capture(
            "defaults read com.apple.Safari IncludeDevelopMenu 2>&1"
        ).strip(),
        "ShowFavoritesBar": env._runner.exec_capture(
            "defaults read com.apple.Safari ShowFavoritesBar 2>&1"
        ).strip(),
        "HomePage": env._runner.exec_capture(
            "defaults read com.apple.Safari HomePage 2>&1"
        ).strip(),
    }
    evidence["safari_processes"] = env._runner.exec_capture(
        "pgrep -fl Safari || echo NONE"
    ).strip()
    evidence["report_file_before_done"] = env._runner.exec_capture(
        "ls -la /Users/lume/Documents/security_audit_report.json 2>&1"
    ).strip()

    # Pull pre_task log (which was already written by the framework)
    evidence["hook_logs_pre_finalize"] = _capture_logs(env, out_dir)

    # Pre-finalize screenshot for clarity in evidence
    env._runner.capture_screenshot(out_dir / "02_before_finalize.png")

    # Finalize (no agent work done; mark_done triggers post_task + verifier)
    log("[do_nothing] mark_done…")
    evidence = _common_flow_finish(env, out_dir, evidence)

    # Final logs after post_task ran
    log("[do_nothing] capturing post-finalize logs")
    # env is closed — can't capture more; rely on what was copied
    (out_dir / "evidence.json").write_text(json.dumps(evidence, indent=2, default=str))
    log(f"[do_nothing] done; evidence in {out_dir}")
    return evidence


# ---------------------------------------------------------------------------
# Flow: wrong_target — agent audits google.com/facebook.com, NOT required
# sites. Strict gate should fire, score = 0.
# ---------------------------------------------------------------------------

def flow_wrong_target(Computer):
    env, obs, out_dir = _common_flow_setup(Computer, "wrong_target")
    evidence = {"flow": "wrong_target", "started_at": time.strftime("%Y-%m-%dT%H:%M:%S")}

    env._runner.capture_screenshot(out_dir / "01_panel_view.png")

    wrong_sites = ["google.com", "facebook.com"]
    log(f"[wrong_target] navigating Safari to {wrong_sites} (no required sites)")
    for i, site in enumerate(wrong_sites, start=1):
        env._runner.exec_capture(
            f"osascript -e 'tell application \"Safari\" to set URL of front document to \"https://{site}/\"'"
        )
        time.sleep(5)
        env._runner.capture_screenshot(out_dir / f"02_navigated_{i}_{site.replace('.', '_')}.png")

    # Write a report mentioning ONLY wrong sites — uses curl for real-looking headers
    log("[wrong_target] writing report containing only google.com/facebook.com")
    write_script = """
python3 << 'PY'
import json, os, subprocess
SITES = ["google.com", "facebook.com"]
WANT = ["strict-transport-security", "content-security-policy", "x-content-type-options", "x-frame-options"]
out = {}
for s in SITES:
    r = subprocess.run(["curl", "-sIL", "-A", "Mozilla/5.0", f"https://{s}/"],
                       capture_output=True, text=True, timeout=15)
    headers = {}
    for block in reversed(r.stdout.replace("\\r\\n", "\\n").split("\\n\\n")):
        if block.strip():
            for line in block.splitlines():
                if ":" in line:
                    k, v = line.split(":", 1)
                    headers[k.strip().lower()] = v.strip()
            break
    out[s] = {k: headers[k] for k in WANT if k in headers}
os.makedirs("/Users/lume/Documents", exist_ok=True)
with open("/Users/lume/Documents/security_audit_report.json", "w") as f:
    json.dump(out, f, indent=2)
print("WROTE", "/Users/lume/Documents/security_audit_report.json", "sites=", list(out.keys()))
PY
"""
    write_log = env._runner.exec_capture(write_script)
    evidence["report_write_log"] = write_log

    # CRITICAL: save the actual report content before sandbox destruction
    _save_remote(env, "/Users/lume/Documents/security_audit_report.json",
                 out_dir / "agent_report.json")

    env._runner.capture_screenshot(out_dir / "03_before_finalize.png")

    log("[wrong_target] mark_done…")
    evidence = _common_flow_finish(env, out_dir, evidence)
    (out_dir / "evidence.json").write_text(json.dumps(evidence, indent=2, default=str))
    log(f"[wrong_target] done; evidence in {out_dir}")
    return evidence


# ---------------------------------------------------------------------------
# Flow: happy_path — simulator navigates 5 required sites + writes a
# real-headers report. Should score near 100.
# ---------------------------------------------------------------------------

def flow_happy_path(Computer):
    env, obs, out_dir = _common_flow_setup(Computer, "happy_path")
    evidence = {"flow": "happy_path", "started_at": time.strftime("%Y-%m-%dT%H:%M:%S")}

    env._runner.capture_screenshot(out_dir / "01_panel_view.png")
    evidence["safari_processes_at_start"] = env._runner.exec_capture(
        "pgrep -fl Safari || echo NONE"
    ).strip()

    sites = ["github.com", "gitlab.com", "bitbucket.org", "npmjs.com", "pypi.org"]
    log(f"[happy_path] navigating Safari to {sites}")
    for i, site in enumerate(sites, start=1):
        log(f"  -> {site}")
        env._runner.exec_capture(
            f"osascript -e 'tell application \"Safari\" to set URL of front document to \"https://{site}/\"'"
        )
        time.sleep(5)
        env._runner.capture_screenshot(out_dir / f"02_visited_{i}_{site.replace('.', '_')}.png")

    log("[happy_path] writing real-headers report via curl")
    write_script = """
python3 << 'PY'
import json, os, subprocess
SITES = ["github.com", "gitlab.com", "bitbucket.org", "npmjs.com", "pypi.org"]
WANT = ["strict-transport-security", "content-security-policy",
        "content-security-policy-report-only",
        "x-content-type-options", "x-frame-options"]
out = {}
for s in SITES:
    # Use GET (-X GET via -sL) instead of HEAD so the response includes the
    # complete CDN-rendered header set; some sites (gitlab) serve sparse
    # responses to HEAD.
    r = subprocess.run(
        ["curl", "-sL", "-A", "Mozilla/5.0", "-D", "-", "-o", "/dev/null", f"https://{s}/"],
        capture_output=True, text=True, timeout=20)
    headers = {}
    for block in reversed(r.stdout.replace("\\r\\n", "\\n").split("\\n\\n")):
        if block.strip():
            for line in block.splitlines():
                if ":" in line:
                    k, v = line.split(":", 1)
                    headers[k.strip().lower()] = v.strip()
            break
    out[s] = {k: headers[k] for k in WANT if k in headers}
os.makedirs("/Users/lume/Documents", exist_ok=True)
with open("/Users/lume/Documents/security_audit_report.json", "w") as f:
    json.dump(out, f, indent=2)
print("WROTE", "/Users/lume/Documents/security_audit_report.json")
for s, e in out.items():
    print(f"  {s}: {len(e)} headers — {list(e.keys())}")
PY
"""
    write_log = env._runner.exec_capture(write_script)
    evidence["report_write_log"] = write_log
    log(write_log)

    # CRITICAL: save the actual report before sandbox destruction
    _save_remote(env, "/Users/lume/Documents/security_audit_report.json",
                 out_dir / "agent_report.json")

    # Standalone run of export_result.sh for evidence of what it produces
    log("[happy_path] running export_result.sh standalone to capture its output")
    export_out = env._runner.exec_capture(
        "bash /Users/lume/workspace/tasks/devtools_security_header_audit/export_result.sh 2>&1"
    )
    (out_dir / "export_script_output.txt").write_text(export_out)
    # Pull the result JSON the export produced
    _save_remote(env, "/tmp/devtools_security_header_audit_result.json",
                 out_dir / "export_result_json.json")

    # Pre-finalize screenshot (Safari still visible)
    env._runner.capture_screenshot(out_dir / "03_before_finalize.png")

    # Pre-finalize logs (some may be overwritten by export_result.sh re-runs
    # when mark_done triggers another execution).
    evidence["hook_logs_pre_finalize"] = _capture_logs(env, out_dir)

    log("[happy_path] mark_done…")
    evidence = _common_flow_finish(env, out_dir, evidence)
    (out_dir / "evidence.json").write_text(json.dumps(evidence, indent=2, default=str))
    log(f"[happy_path] done; evidence in {out_dir}")
    return evidence


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--flow", default="all",
                        choices=["all", "probe_prefs", "do_nothing", "wrong_target", "happy_path"])
    args = parser.parse_args()

    if not os.environ.get("USE_COMPUTER_API_KEY"):
        sys.exit("USE_COMPUTER_API_KEY must be set")
    if not os.environ.get("USE_COMPUTER_BASE_URL"):
        os.environ["USE_COMPUTER_BASE_URL"] = "https://api.use.computer"

    import logging
    logging.basicConfig(level=logging.WARNING,
                        format="%(asctime)s %(name)s %(levelname)s %(message)s")

    from use_computer import Computer

    ensure_dir(EVIDENCE_ROOT)
    summary = {"runs": []}

    flows = ["probe_prefs", "do_nothing", "wrong_target", "happy_path"] if args.flow == "all" else [args.flow]
    for flow in flows:
        log(f"=== starting flow: {flow} ===")
        try:
            if flow == "probe_prefs":
                result = flow_probe_prefs(Computer)
            elif flow == "do_nothing":
                result = flow_do_nothing(Computer)
            elif flow == "wrong_target":
                result = flow_wrong_target(Computer)
            elif flow == "happy_path":
                result = flow_happy_path(Computer)
            summary["runs"].append({"flow": flow, "ok": True})
        except Exception as exc:
            log(f"FLOW {flow} FAILED: {exc}")
            import traceback; traceback.print_exc()
            summary["runs"].append({"flow": flow, "ok": False, "error": str(exc)})

    (EVIDENCE_ROOT / "_collection_summary.json").write_text(json.dumps(summary, indent=2))
    log(f"All flows complete. Evidence root: {EVIDENCE_ROOT}")


if __name__ == "__main__":
    main()
