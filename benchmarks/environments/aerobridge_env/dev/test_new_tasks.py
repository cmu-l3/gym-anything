#!/usr/bin/env python3
"""
Do-nothing tests for the 5 new aerobridge_env tasks.

Each test:
1. Boots from post_start cache
2. Runs the setup_task.sh (pre_task hook) via SSH
3. Runs the export_result.sh (post_task hook) via SSH  WITHOUT doing the task
4. Runs the verifier to confirm score=0 (do-nothing protection)
5. Saves a screenshot + evidence JSON

Run: python3 benchmarks/environments/aerobridge_env/dev/test_new_tasks.py
"""

import os
import sys
import json
import time
import tempfile
import importlib.util
import paramiko

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))))

from gym_anything.api import from_config
from gym_anything.runners.vnc_utils import VNCConnection

TASKS_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "tasks")
EVIDENCE_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "evidence")
os.makedirs(EVIDENCE_DIR, exist_ok=True)

NEW_TASKS = [
    "update_operator_authorizations",
    "create_survey_mission",
    "register_aircraft_model_chain",
    "setup_new_operator_company",
    "register_aircraft_with_detail",
]


def ssh_connect(ssh_port, username="ga", password="password123", timeout=60):
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect("localhost", port=ssh_port, username=username, password=password, timeout=timeout)
    return client


def ssh_run(client, cmd, timeout=600):
    """Run cmd via SSH; blocks until command finishes (no recv timeout)."""
    # timeout=None means no recv timeout — blocks until the process exits
    transport = client.get_transport()
    channel = transport.open_session()
    channel.settimeout(None)          # no per-recv timeout; block until EOF
    channel.exec_command(cmd)
    # Read stdout/stderr fully (blocks until channel closes)
    out_bytes = b""
    err_bytes = b""
    while True:
        if channel.recv_ready():
            chunk = channel.recv(4096)
            if chunk:
                out_bytes += chunk
        if channel.recv_stderr_ready():
            chunk = channel.recv_stderr(4096)
            if chunk:
                err_bytes += chunk
        if channel.exit_status_ready():
            # Drain any remaining data
            while channel.recv_ready():
                out_bytes += channel.recv(4096)
            while channel.recv_stderr_ready():
                err_bytes += channel.recv_stderr(4096)
            break
        time.sleep(0.1)
    rc = channel.recv_exit_status()
    channel.close()
    return rc, out_bytes.decode(errors="replace"), err_bytes.decode(errors="replace")


def load_verifier(task_name):
    verifier_path = os.path.join(TASKS_DIR, task_name, "verifier.py")
    spec = importlib.util.spec_from_file_location(f"verifier_{task_name}", verifier_path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    fn_name = f"verify_{task_name}"
    return getattr(mod, fn_name)


def make_copy_from_env(ssh_client):
    """Returns a copy_from_env function that copies files from the VM via SFTP."""
    def copy_from_env(vm_path, host_path):
        sftp = ssh_client.open_sftp()
        try:
            sftp.get(vm_path, host_path)
        finally:
            sftp.close()
    return copy_from_env


def take_vnc_screenshot(vnc_port, out_path):
    try:
        vnc = VNCConnection("localhost", vnc_port, password="password")
        vnc.connect()
        img_bytes = vnc.capture_screenshot()
        with open(out_path, "wb") as f:
            f.write(img_bytes)
        try:
            vnc.disconnect()
        except AttributeError:
            pass  # older VNCConnection may not have disconnect()
        return True
    except Exception as e:
        print(f"  [VNC screenshot failed: {e}]")
        return False


def run_task_test(env, task_name, ssh_port, vnc_port):
    print(f"\n{'='*60}")
    print(f"Testing: {task_name}")
    print(f"{'='*60}")

    result = {
        "task": task_name,
        "setup_rc": None,
        "export_rc": None,
        "verifier_result": None,
        "screenshot_saved": False,
        "errors": []
    }

    # Connect SSH
    try:
        client = ssh_connect(ssh_port)
        print(f"  SSH connected on port {ssh_port}")
    except Exception as e:
        result["errors"].append(f"SSH connect failed: {e}")
        print(f"  SSH FAILED: {e}")
        return result

    try:
        # 1. Run setup_task.sh
        setup_script = f"/workspace/tasks/{task_name}/setup_task.sh"
        print(f"  Running setup_task.sh ...")
        rc, out, err = ssh_run(client, f"sudo bash {setup_script}", timeout=300)
        result["setup_rc"] = rc
        print(f"  setup_task.sh exit={rc}")
        if out.strip():
            print(f"  stdout: {out.strip()[:500]}")
        if err.strip():
            print(f"  stderr: {err.strip()[:200]}")
        if rc != 0:
            result["errors"].append(f"setup_task.sh failed with rc={rc}: {err[:200]}")

        # 2. Take screenshot after setup (before doing anything)
        img_path = os.path.join(EVIDENCE_DIR, f"{task_name}_00_after_setup.png")
        if take_vnc_screenshot(vnc_port, img_path):
            result["screenshot_saved"] = True
            print(f"  Screenshot saved: {img_path}")

        # 3. Run export_result.sh WITHOUT doing the task (do-nothing test)
        export_script = f"/workspace/tasks/{task_name}/export_result.sh"
        print(f"  Running export_result.sh (do-nothing) ...")
        rc, out, err = ssh_run(client, f"sudo bash {export_script}", timeout=300)
        result["export_rc"] = rc
        print(f"  export_result.sh exit={rc}")
        if out.strip():
            print(f"  stdout: {out.strip()[:500]}")
        if err.strip():
            print(f"  stderr: {err.strip()[:200]}")
        if rc != 0:
            result["errors"].append(f"export_result.sh failed with rc={rc}: {err[:200]}")

        # 4. Run verifier
        print(f"  Running verifier ...")
        copy_fn = make_copy_from_env(client)
        verify_fn = load_verifier(task_name)
        env_info = {"copy_from_env": copy_fn}
        verifier_result = verify_fn(traj=None, env_info=env_info, task_info={})
        result["verifier_result"] = verifier_result
        print(f"  Score: {verifier_result.get('score', '?')}/100, passed={verifier_result.get('passed', '?')}")
        print(f"  Feedback:\n    " + verifier_result.get("feedback", "").replace("\n", "\n    "))

        # 5. Check that score == 0 (do-nothing protection works)
        score = verifier_result.get("score", -1)
        if score == 0:
            print(f"  ✓ DO-NOTHING PROTECTION: score=0 as expected")
        else:
            print(f"  ✗ WARNING: do-nothing score={score} (expected 0)")
            result["errors"].append(f"Do-nothing gave non-zero score: {score}")

    finally:
        client.close()

    return result


def main():
    print("=== Aerobridge New Tasks Do-Nothing Test ===")
    print(f"Working dir: {os.getcwd()}")

    # Load environment
    env_dir = os.path.dirname(os.path.dirname(__file__))
    print(f"\nLoading env from: {env_dir}")
    env = from_config(env_dir)

    print("Resetting env (use_cache=True, cache_level=post_start) ...")
    obs = env.reset(seed=42, use_cache=True, cache_level="post_start", use_savevm=True)
    print(f"Reset complete. Obs keys: {list(obs.keys()) if isinstance(obs, dict) else type(obs)}")

    ssh_port = env._runner.ssh_port
    vnc_port = getattr(env._runner, 'vnc_port', 6023)
    print(f"SSH port: {ssh_port}, VNC port: {vnc_port}")

    # Wait a moment for services to settle
    time.sleep(5)

    # Run each task test
    all_results = {}
    for task_name in NEW_TASKS:
        r = run_task_test(env, task_name, ssh_port, vnc_port)
        all_results[task_name] = r

    # Summary
    print(f"\n{'='*60}")
    print("SUMMARY")
    print(f"{'='*60}")
    all_pass = True
    for task_name, r in all_results.items():
        vr = r.get("verifier_result") or {}
        score = vr.get("score", "N/A")
        errors = r.get("errors", [])
        status = "OK" if score == 0 and not errors else "ISSUE"
        if status == "ISSUE":
            all_pass = False
        print(f"  {task_name}: score={score} setup_rc={r['setup_rc']} export_rc={r['export_rc']} [{status}]")
        for e in errors:
            print(f"    ERROR: {e}")

    # Save evidence JSON
    evidence = {
        "test_date": time.strftime("%Y-%m-%d"),
        "test_type": "do_nothing",
        "all_tasks_score_0": all_pass,
        "results": {
            k: {
                "setup_rc": v["setup_rc"],
                "export_rc": v["export_rc"],
                "score": (v["verifier_result"] or {}).get("score", None),
                "passed": (v["verifier_result"] or {}).get("passed", None),
                "feedback": (v["verifier_result"] or {}).get("feedback", ""),
                "errors": v["errors"]
            }
            for k, v in all_results.items()
        }
    }
    evidence_path = os.path.join(EVIDENCE_DIR, "new_tasks_do_nothing_results.json")
    with open(evidence_path, "w") as f:
        json.dump(evidence, f, indent=2)
    print(f"\nEvidence saved to: {evidence_path}")

    env.close()
    print("\nDone.")
    return 0 if all_pass else 1


if __name__ == "__main__":
    sys.exit(main())
