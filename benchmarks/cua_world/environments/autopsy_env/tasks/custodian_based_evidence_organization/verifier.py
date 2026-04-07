#!/usr/bin/env python3
"""
Verifier for custodian_based_evidence_organization task.

Scoring (100 pts total, pass threshold = 60):
  15 pts  — Autopsy case created and DB found
  15 pts  — Both disk images added to the DB
  20 pts  — Person entities created (Alice_Chen, Bob_Smith)
  20 pts  — Host entities created (Alice_USB, Bob_Camera)
  20 pts  — Manifest CSV file exists, is recent, and correctly formatted
  10 pts  — Summary text file exists and is recent
"""

import json
import os
import tempfile


def verify_custodian_organization(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/custodian_result.json")

    # ── Pull result JSON ──────────────────────────────────────────────────────
    result = {}
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env(result_file_vm, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — task was not attempted or export did not run."
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # ── Criterion 1: Case DB found (15 pts) ───────────────────────────────────
    if result.get("case_db_found"):
        score += 15
        feedback_parts.append("PASS Case DB found (+15)")
    else:
        feedback_parts.append("FAIL Case DB not found")

    # ── Criterion 2: Data sources added (15 pts) ──────────────────────────────
    db_ds = [str(x).lower() for x in result.get("db_data_sources", [])]
    has_img1 = any("ntfs_undel" in ds for ds in db_ds)
    has_img2 = any("jpeg_search" in ds for ds in db_ds)

    if has_img1 and has_img2:
        score += 15
        feedback_parts.append("PASS Both disk images added (+15)")
    elif has_img1 || has_img2:
        score += 7
        feedback_parts.append("PARTIAL Only one disk image added (+7)")
    else:
        feedback_parts.append("FAIL Disk images not found in case")

    # ── Criterion 3: Person entities created (20 pts) ─────────────────────────
    db_persons = [str(x).lower() for x in result.get("db_persons", [])]
    has_alice = any("alice" in p for p in db_persons)
    has_bob = any("bob" in p for p in db_persons)

    if has_alice and has_bob:
        score += 20
        feedback_parts.append("PASS Both Persons (Alice_Chen, Bob_Smith) found in DB (+20)")
    elif has_alice or has_bob:
        score += 10
        feedback_parts.append("PARTIAL Only one Person found in DB (+10)")
    else:
        feedback_parts.append("FAIL Persons not created in DB")

    # ── Criterion 4: Host entities created (20 pts) ───────────────────────────
    db_hosts = [str(x).lower() for x in result.get("db_hosts", [])]
    has_alice_host = any("alice" in h for h in db_hosts)
    has_bob_host = any("bob" in h for h in db_hosts)

    if has_alice_host and has_bob_host:
        score += 20
        feedback_parts.append("PASS Both Hosts (Alice_USB, Bob_Camera) found in DB (+20)")
    elif has_alice_host or has_bob_host:
        score += 10
        feedback_parts.append("PARTIAL Only one Host found in DB (+10)")
    else:
        feedback_parts.append("FAIL Hosts not created in DB")

    # ── Criterion 5: Manifest CSV format (20 pts) ─────────────────────────────
    start_time = result.get("start_time", 0)
    manifest_mtime = result.get("manifest_mtime", 0)
    manifest_content = result.get("manifest_content", "").replace("\\n", "\n")

    if result.get("manifest_file_exists"):
        is_recent = (start_time == 0 or manifest_mtime >= start_time)
        lines = [l.strip() for l in manifest_content.splitlines() if l.strip()]
        
        has_header = any("PERSON" in l.upper() and "HOST" in l.upper() and "DATA" in l.upper() for l in lines[:2])
        has_alice_row = any("alice" in l.lower() and "ntfs" in l.lower() for l in lines)
        has_bob_row = any("bob" in l.lower() and "jpeg" in l.lower() for l in lines)

        if is_recent and has_header and has_alice_row and has_bob_row:
            score += 20
            feedback_parts.append("PASS Manifest CSV is perfectly formatted and recent (+20)")
        elif is_recent and len(lines) >= 2:
            score += 10
            feedback_parts.append("PARTIAL Manifest CSV exists and is recent but lacks expected mappings (+10)")
        else:
            score += 5
            feedback_parts.append("PARTIAL Manifest CSV exists but might be stale or malformed (+5)")
    else:
        feedback_parts.append("FAIL Manifest CSV not found")

    # ── Criterion 6: Summary file (10 pts) ────────────────────────────────────
    summary_mtime = result.get("summary_mtime", 0)
    if result.get("summary_file_exists"):
        if start_time == 0 or summary_mtime >= start_time:
            score += 10
            feedback_parts.append("PASS Summary file exists and is recent (+10)")
        else:
            score += 5
            feedback_parts.append("PARTIAL Summary file exists but might be stale (+5)")
    else:
        feedback_parts.append("FAIL Summary file not found")

    # ── Final determination ───────────────────────────────────────────────────
    passed = score >= 60 and result.get("case_db_found") and (has_alice or has_bob)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }