#!/usr/bin/env python3
"""
Verifier for mbr_wiped_partition_recovery task.

Scoring (100 pts total, pass threshold = 65):
  25 pts  — Extracted volume exists and has perfect MD5 hash match with ground truth
  20 pts  — Recovery report correctly identifies exact sector offset (2048)
  15 pts  — Autopsy case created and recovered volume added as data source
  20 pts  — Recovered volume parsed by Autopsy and files populated in DB
  20 pts  — Root inventory CSV exists with pipe-delimited records
"""

import json
import os
import re
import tempfile

def verify_mbr_recovery(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/mbr_recovery_result.json")
    expected_offset = meta.get("expected_offset", 2048)

    # ── Pull result JSON from VM ──────────────────────────────────────────────
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        
        copy_from_env = env_info.get("copy_from_env")
        if not copy_from_env:
            return {"passed": False, "score": 0, "feedback": "Copy function not available"}
            
        copy_from_env(result_file_vm, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export script did not run or task was not attempted."
        }
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read result file: {e}"
        }

    # ── Criterion 1: Extracted volume exists and hash matches (25 pts) ────────
    if result.get("recovered_volume_exists"):
        if result.get("recovered_volume_hash_match"):
            score += 25
            feedback_parts.append("PASS Extracted volume exists and has perfect MD5 hash match (+25)")
        else:
            score += 10
            feedback_parts.append("PARTIAL Extracted volume exists but MD5 hash does not match expected GT exactly (+10)")
    else:
        feedback_parts.append("FAIL Recovered volume not found at /home/ga/evidence/recovered_volume.dd")

    # ── Criterion 2: Offset calculation in report (20 pts) ────────────────────
    if result.get("report_exists"):
        report_content = result.get("report_content", "")
        # Look for PARTITION_OFFSET_SECTORS: 2048
        offset_match = re.search(r'PARTITION_OFFSET_SECTORS:\s*(\d+)', report_content, re.IGNORECASE)
        if offset_match:
            agent_offset = int(offset_match.group(1))
            if agent_offset == expected_offset:
                score += 20
                feedback_parts.append(f"PASS Report correctly identifies sector offset {expected_offset} (+20)")
            else:
                feedback_parts.append(f"FAIL Report offset incorrect: got {agent_offset}, expected {expected_offset}")
        else:
            feedback_parts.append("FAIL Sector offset not found in recovery report")
    else:
        feedback_parts.append("FAIL Recovery report not found")

    # ── Criterion 3: Autopsy Case Creation (15 pts) ───────────────────────────
    if result.get("case_db_found"):
        if result.get("data_source_added"):
            score += 15
            feedback_parts.append("PASS Case created and recovered volume added as data source (+15)")
        else:
            score += 5
            feedback_parts.append("PARTIAL Case created but data source not added (+5)")
    else:
        feedback_parts.append("FAIL Autopsy case MBR_Recovery_2026 not found")

    # ── Criterion 4: Autopsy DB Population (20 pts) ───────────────────────────
    if result.get("db_files_populated"):
        score += 20
        feedback_parts.append("PASS Recovered volume parsed by Autopsy and files populated in DB (+20)")
    else:
        feedback_parts.append("FAIL No files populated in Autopsy DB")

    # ── Criterion 5: Root Inventory (20 pts) ──────────────────────────────────
    if result.get("inventory_exists"):
        inv_content = result.get("inventory_content", "")
        lines = [l.strip() for l in inv_content.splitlines() if l.strip()]
        
        # Check if there are at least 3 lines and they have pipe delimiters
        data_lines = [l for l in lines if "|" in l]
        
        if len(data_lines) > 2:
            score += 20
            feedback_parts.append("PASS Root inventory CSV exists with pipe-delimited records (+20)")
        elif len(data_lines) > 0:
            score += 10
            feedback_parts.append("PARTIAL Root inventory has some pipe-delimited records but may be incomplete (+10)")
        elif len(lines) > 0:
            score += 5
            feedback_parts.append("PARTIAL Root inventory exists but format may be incorrect (no pipe delimiters) (+5)")
        else:
            feedback_parts.append("FAIL Root inventory is empty")
    else:
        feedback_parts.append("FAIL Root inventory CSV not found")

    # ── Final Evaluation ──────────────────────────────────────────────────────
    key_criteria_met = result.get("recovered_volume_hash_match") and result.get("report_exists")
    passed = (score >= 65) and key_criteria_met

    if passed:
        feedback_parts.insert(0, f"TASK PASSED (Score: {score}/100)")
    else:
        feedback_parts.insert(0, f"TASK FAILED (Score: {score}/100)")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }