#!/usr/bin/env python3
"""Programmatic verifier for import_us_senators_leads task.

This verifier checks Vicidial's MySQL (inside the Docker container) to confirm:
1) List ID 9001 exists.
2) Lead count for list 9001 matches the provided CSV row count.
"""

from __future__ import annotations

from dataclasses import dataclass


def verify_import_us_senators_leads(traj, env_info, task_info):
    exec_capture = env_info.get("exec_capture")
    if not exec_capture:
        return {
            "passed": False,
            "score": 0,
            "feedback": "exec_capture not available; cannot query Vicidial DB for verification",
        }

    list_id = "9001"
    csv_path = "/home/ga/Documents/VicidialData/us_senators_vicidial_standard_format_list9001_2026-02-14.csv"

    def sh(cmd: str) -> str:
        return (exec_capture(cmd) or "").strip()

    @dataclass
    class Check:
        ok: bool
        msg: str

    checks: list[Check] = []

    # Ensure container is running
    container_running = bool(sh("docker ps -q -f name=vicidial -f status=running"))
    checks.append(Check(container_running, "vicidial container is running"))
    if not container_running:
        return {"passed": False, "score": 0, "feedback": " | ".join(c.msg for c in checks if not c.ok)}

    # Determine expected row count from the CSV file present in the VM.
    expected_raw = sh(f"wc -l '{csv_path}' 2>/dev/null | awk '{{print $1}}' || true")
    try:
        expected_count = int(expected_raw) if expected_raw else 0
    except ValueError:
        expected_count = 0
    checks.append(Check(expected_count > 0, f"expected CSV rows: {expected_count}"))
    if expected_count <= 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CSV missing/unreadable at {csv_path} (wc -l returned '{expected_raw}')",
        }

    # Query DB for list existence and lead count.
    list_count_raw = sh(
        "docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "
        f"\"SELECT COUNT(*) FROM vicidial_lists WHERE list_id='{list_id}';\" 2>/dev/null || true"
    )
    leads_count_raw = sh(
        "docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "
        f"\"SELECT COUNT(*) FROM vicidial_list WHERE list_id='{list_id}';\" 2>/dev/null || true"
    )

    try:
        list_count = int(list_count_raw) if list_count_raw else 0
    except ValueError:
        list_count = 0
    try:
        leads_count = int(leads_count_raw) if leads_count_raw else 0
    except ValueError:
        leads_count = 0

    checks.append(Check(list_count == 1, f"list {list_id} exists (count={list_count})"))
    checks.append(Check(leads_count == expected_count, f"leads in list {list_id}: {leads_count}/{expected_count}"))

    passed = all(c.ok for c in checks)
    score = 100 if passed else max(0, min(99, int(round(100 * (leads_count / max(1, expected_count)))))))

    feedback = " | ".join(
        [("OK: " if c.ok else "FAIL: ") + c.msg for c in checks]
    )
    if not passed:
        feedback += " | Hint: verify list 9001 was created in the UI and the CSV was imported via List Loader (Standard Format)."

    return {"passed": passed, "score": score, "feedback": feedback}
