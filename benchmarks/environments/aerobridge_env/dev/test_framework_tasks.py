#!/usr/bin/env python3
"""
Framework-level test for the 5 new aerobridge_env tasks.

Tests:
1. Do-nothing test — env.reset() (runs pre_task), env.step([], mark_done=True)
   without taking agent actions -> expect score=0, passed=False
2. Wrong-target test — inject the payload that the export_result.sh would produce
   when the agent operated on the WRONG entity (null/unchanged baseline)
   -> expect score=0, passed=False
3. Partial completion test — inject a result with only SOME subtasks done
   -> expect 0 < score < pass_threshold, passed=False

Run from repo root: python3 benchmarks/environments/aerobridge_env/dev/test_framework_tasks.py
"""

import os, sys, json, time, tempfile, importlib.util, paramiko

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))))

from gym_anything.api import from_config

ENV_DIR   = os.path.join(os.path.dirname(os.path.dirname(__file__)))
TASKS_DIR = os.path.join(ENV_DIR, "tasks")
EVIDENCE_DIR = os.path.join(ENV_DIR, "evidence")
os.makedirs(EVIDENCE_DIR, exist_ok=True)

NEW_TASKS = [
    "update_operator_authorizations",
    "create_survey_mission",
    "register_aircraft_model_chain",
    "setup_new_operator_company",
    "register_aircraft_with_detail",
]

# Wrong-target payloads: what the export returns when the WRONG entity is modified.
# For edit tasks: target entity is unchanged (agent edited a different record).
# For create tasks: target name not found (agent created with wrong name).
WRONG_TARGET_PAYLOADS = {
    # Agent edited A.J. August Photography (wrong operator).
    # Export still queries Electric Inspection by name but reports it UNCHANGED.
    # Verifier sees unchanged baseline -> all checks fail -> score=0.
    "update_operator_authorizations": {
        "task": "update_operator_authorizations",
        "operator": {
            "id": "566d63bb-cb1c-42dc-9a51-baef0d0a8d04",
            "company_full_name": "Electric Inspection",
            "operator_type": 0,
            "authorized_activities": ["photographing"],
            "operational_authorizations": ["SORA V2"]
        },
        "error": None
    },
    "create_survey_mission": {
        "flight_plan": None,
        "flight_operation": None,
        "error": None
    },
    "register_aircraft_model_chain": {
        "aircraft_model": None,
        "aircraft_assembly": None,
        "aircraft": None,
        "error": None
    },
    "setup_new_operator_company": {
        "company": None,
        "operator": None,
        "error": None
    },
    "register_aircraft_with_detail": {
        "aircraft": None,
        "aircraft_detail": None,
        "flight_operation": None,
        "error": None
    },
}

# Partial payloads: only SOME required subtasks are completed.
PARTIAL_PAYLOADS = {
    # Only operator_type updated (30pts); activities/auths still at baseline.
    # Expected: score=30, passed=False (threshold 50).
    "update_operator_authorizations": {
        "task": "update_operator_authorizations",
        "operator": {
            "id": "566d63bb-cb1c-42dc-9a51-baef0d0a8d04",
            "company_full_name": "Electric Inspection",
            "operator_type": 2,
            "authorized_activities": ["photographing"],
            "operational_authorizations": ["SORA V2"]
        },
        "error": None
    },
    # FlightPlan created correctly; FlightOperation not yet created.
    "create_survey_mission": {
        "flight_plan": {
            "id": "aaaaaaaa-1111-2222-3333-444444444444",
            "name": "Kolkata Port Survey",
            "geo_json": '{"type":"Polygon","coordinates":[[[88.35,22.57],[88.40,22.57],[88.40,22.60],[88.35,22.60],[88.35,22.57]]]}',
            "is_editable": True
        },
        "flight_operation": None,
        "error": None
    },
    # AircraftModel created; no assembly or aircraft yet.
    "register_aircraft_model_chain": {
        "aircraft_model": {
            "id": "bbbbbbbb-1111-2222-3333-444444444444",
            "name": "Nile Scout 200",
            "category": 2,
            "category_name": "ROTORCRAFT"
        },
        "aircraft_assembly": None,
        "aircraft": None,
        "error": None
    },
    # Company created with correct attributes; no Operator linked yet.
    "setup_new_operator_company": {
        "company": {
            "id": "cccccccc-1111-2222-3333-444444444444",
            "full_name": "BlueSky Robotics Pvt Ltd",
            "role": 2,
            "country": "IN"
        },
        "operator": None,
        "error": None
    },
    # Aircraft created correctly; no AircraftDetail and no FlightOperation yet.
    "register_aircraft_with_detail": {
        "aircraft": {
            "id": "dddddddd-1111-2222-3333-444444444444",
            "name": "Falcon Eye 3",
            "flight_controller_id": "FE3CTRL334455",
            "status": 1,
            "has_assembly": True
        },
        "aircraft_detail": None,
        "flight_operation": None,
        "error": None
    },
}


def ssh_connect(ssh_port, username="ga", password="password123"):
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect("localhost", port=ssh_port, username=username, password=password, timeout=60)
    return client


def ssh_run_channel(client, cmd):
    transport = client.get_transport()
    channel = transport.open_session()
    channel.settimeout(None)
    channel.exec_command(cmd)
    out_bytes, err_bytes = b"", b""
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
            while channel.recv_ready():
                out_bytes += channel.recv(4096)
            while channel.recv_stderr_ready():
                err_bytes += channel.recv_stderr(4096)
            break
        time.sleep(0.1)
    rc = channel.recv_exit_status()
    channel.close()
    return rc, out_bytes.decode(errors="replace"), err_bytes.decode(errors="replace")


def inject_result(ssh_client, task_name, payload):
    """Write a crafted JSON into the VM result file via sudo python3 stdin."""
    json_bytes = json.dumps(payload, indent=2).encode()
    transport = ssh_client.get_transport()
    channel = transport.open_session()
    channel.settimeout(None)
    dest = f"/tmp/{task_name}_result.json"
    channel.exec_command(
        f"sudo python3 -c \"import sys; open('{dest}', 'wb').write(sys.stdin.buffer.read())\""
    )
    channel.sendall(json_bytes)
    channel.shutdown_write()
    channel.recv_exit_status()
    channel.close()


def make_copy_fn(ssh_client):
    def copy_from_env(vm_path, host_path):
        sftp = ssh_client.open_sftp()
        try:
            sftp.get(vm_path, host_path)
        finally:
            sftp.close()
    return copy_from_env


def load_verifier(task_name):
    path = os.path.join(TASKS_DIR, task_name, "verifier.py")
    spec = importlib.util.spec_from_file_location(f"verifier_{task_name}", path)
    mod  = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return getattr(mod, f"verify_{task_name}")


def run_verifier_direct(ssh_client, task_name):
    fn = load_verifier(task_name)
    env_info = {"copy_from_env": make_copy_fn(ssh_client)}
    return fn(traj=None, env_info=env_info, task_info={})


def test_task(task_name):
    print(f"\n{'='*65}")
    print(f"TASK: {task_name}")
    print(f"{'='*65}")

    results = {"task": task_name, "do_nothing": None, "wrong_target": None, "partial": None, "errors": []}

    env = from_config(ENV_DIR, task_id=task_name)
    ssh_port = None
    try:
        # Test 1: Do-Nothing via gym framework --------------------------------
        print("\n[Test 1] Do-Nothing (framework: reset -> step mark_done)")
        obs = env.reset(seed=42, use_cache=True, cache_level="post_start", use_savevm=True)
        ssh_port = env._runner.ssh_port
        print(f"  SSH port: {ssh_port}")

        obs2, reward, done, info = env.step([], mark_done=True)
        vr    = info.get("verifier", {})
        score = vr.get("score", -1)
        passed = vr.get("passed", None)
        print(f"  score={score}, passed={passed}")
        print("  feedback:\n    " + str(vr.get("feedback", "")).replace("\n", "\n    "))
        if score == 0 and passed is False:
            print("  OK do-nothing score=0")
        else:
            msg = f"do-nothing score={score} passed={passed} (expected 0/False)"
            print(f"  FAIL: {msg}")
            results["errors"].append(msg)
        results["do_nothing"] = {"score": score, "passed": passed}

        # Tests 2 & 3 via SSH injection ----------------------------------------
        # Test 2: Wrong-Target -------------------------------------------------
        print("\n[Test 2] Wrong-Target (inject null/unchanged payload)")
        ssh = ssh_connect(ssh_port)
        try:
            inject_result(ssh, task_name, WRONG_TARGET_PAYLOADS[task_name])
            wr = run_verifier_direct(ssh, task_name)
            ws, wp = wr.get("score", -1), wr.get("passed")
            print(f"  score={ws}, passed={wp}")
            print("  feedback:\n    " + str(wr.get("feedback", "")).replace("\n", "\n    "))
            if ws == 0 and wp is False:
                print("  OK wrong-target score=0")
            else:
                msg = f"wrong-target score={ws} passed={wp} (expected 0/False)"
                print(f"  FAIL: {msg}")
                results["errors"].append(msg)
            results["wrong_target"] = {"score": ws, "passed": wp}
        finally:
            ssh.close()

        # Test 3: Partial Completion -------------------------------------------
        print("\n[Test 3] Partial Completion (inject partial payload)")
        ssh = ssh_connect(ssh_port)
        try:
            inject_result(ssh, task_name, PARTIAL_PAYLOADS[task_name])
            pr = run_verifier_direct(ssh, task_name)
            ps, pp = pr.get("score", -1), pr.get("passed")
            print(f"  score={ps}, passed={pp}")
            print("  feedback:\n    " + str(pr.get("feedback", "")).replace("\n", "\n    "))
            if 0 < ps < 100 and pp is False:
                print(f"  OK partial score={ps} in (0,100)")
            else:
                msg = f"partial score={ps} passed={pp} (expected 0<score<100, False)"
                print(f"  FAIL: {msg}")
                results["errors"].append(msg)
            results["partial"] = {"score": ps, "passed": pp}
        finally:
            ssh.close()

    except Exception as e:
        print(f"  EXCEPTION: {e}")
        results["errors"].append(str(e))
        import traceback; traceback.print_exc()
    finally:
        try:
            env.close()
        except Exception:
            pass

    return results


def main():
    print("=== Aerobridge Framework Tests (do-nothing + wrong-target + partial) ===\n")
    all_results = {}
    for task_name in NEW_TASKS:
        all_results[task_name] = test_task(task_name)

    print(f"\n{'='*65}")
    print("FINAL SUMMARY")
    print(f"{'='*65}")
    all_ok = True
    for task_name, r in all_results.items():
        dn = (r.get("do_nothing") or {})
        wt = (r.get("wrong_target") or {})
        pt = (r.get("partial") or {})
        errors = r.get("errors", [])
        ok = (dn.get("score") == 0 and wt.get("score") == 0 and
              0 < (pt.get("score") or 0) < 100 and not errors)
        if not ok:
            all_ok = False
        status = "ALL_PASS" if ok else "ISSUE"
        print(f"  {task_name}: dn={dn.get('score')} wt={wt.get('score')} partial={pt.get('score')} [{status}]")
        for e in errors:
            print(f"    ERROR: {e}")

    evidence = {
        "test_date": time.strftime("%Y-%m-%d"),
        "test_type": "framework_do_nothing_wrong_target_partial",
        "all_tests_passed": all_ok,
        "results": {
            k: {
                "do_nothing_score": (v.get("do_nothing") or {}).get("score"),
                "do_nothing_passed": (v.get("do_nothing") or {}).get("passed"),
                "wrong_target_score": (v.get("wrong_target") or {}).get("score"),
                "wrong_target_passed": (v.get("wrong_target") or {}).get("passed"),
                "partial_score": (v.get("partial") or {}).get("score"),
                "partial_passed": (v.get("partial") or {}).get("passed"),
                "errors": v.get("errors", [])
            }
            for k, v in all_results.items()
        }
    }
    out_path = os.path.join(EVIDENCE_DIR, "framework_tests_results.json")
    with open(out_path, "w") as f:
        json.dump(evidence, f, indent=2)
    print(f"\nEvidence saved to: {out_path}")
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
