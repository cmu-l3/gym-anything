#!/usr/bin/env python3
"""
Verifier for targeted_ingest_filtering_workflow task.

Scoring (100 pts total, pass threshold = 75):
  10 pts  — Autopsy case created and DB found
  10 pts  — Disk image data source added to case
  20 pts  — 'Warrant_Scope' custom filter name found in Autopsy logs
  20 pts  — In-scope files were processed (Hash/MIME metadata generated)
  25 pts  — Out-of-scope files were IGNORED (CRITICAL: Hash/MIME NOT generated)
  15 pts  — Audit report exists and contains required verification statements
"""

import json
import os
import tempfile

def verify_targeted_ingest_filtering_workflow(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/targeted_ingest_result.json")

    # ── Pull result JSON from VM ──────────────────────────────────────────────
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        env_info["copy_from_env"](result_file_vm, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found \u2014 export script did not run or task was not attempted."
        }
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read result file: {e}"
        }

    # ── Criterion 1: Case DB found (10 pts) ───────────────────────────────────
    if result.get("case_db_found"):
        score += 10
        feedback_parts.append("PASS Case DB found for Targeted_Ingest_2024 (+10)")
    else:
        feedback_parts.append("FAIL Case DB not found — case may not have been created")

    # ── Criterion 2: Data source added (10 pts) ───────────────────────────────
    if result.get("data_source_added"):
        score += 10
        feedback_parts.append("PASS Data source added to case (+10)")
    else:
        feedback_parts.append("FAIL Data source not found in case DB")

    # ── Criterion 3: Filter Logged (20 pts) ───────────────────────────────────
    if result.get("filter_logged"):
        score += 20
        feedback_parts.append("PASS Custom filter 'Warrant_Scope' identified in Autopsy logs (+20)")
    else:
        feedback_parts.append("FAIL 'Warrant_Scope' filter string not found in Autopsy logs")

    # ── Criterion 4: In-scope Processed (20 pts) ──────────────────────────────
    in_scope_hashed = result.get("in_scope_hashed_count", 0)
    in_scope_mime = result.get("in_scope_mime_count", 0)
    
    if in_scope_hashed > 0 or in_scope_mime > 0:
        score += 20
        feedback_parts.append(f"PASS In-scope files successfully processed (Hash: {in_scope_hashed}, MIME: {in_scope_mime}) (+20)")
    else:
        feedback_parts.append("FAIL No in-scope files were processed (Ingest may not have been run)")

    # ── Criterion 5: Out-of-scope Ignored (25 pts) ────────────────────────────
    # This is the critical constraint — if the agent violates the warrant scope, they fail this check.
    out_of_scope_hashed = result.get("out_of_scope_hashed_count", -1)
    out_of_scope_mime = result.get("out_of_scope_mime_count", -1)
    out_ignored = False
    
    if out_of_scope_hashed == 0 and out_of_scope_mime == 0:
        score += 25
        out_ignored = True
        feedback_parts.append("PASS Out-of-scope files successfully IGNORED during ingest (+25)")
    else:
        feedback_parts.append(f"FAIL Out-of-scope files were incorrectly processed (Hash: {out_of_scope_hashed}, MIME: {out_of_scope_mime})")

    # ── Criterion 6: Audit Report (15 pts) ────────────────────────────────────
    start_time = result.get("start_time", 0)
    report_mtime = result.get("audit_report_mtime", 0)
    report_content = result.get("audit_report_content", "").upper()
    
    has_extensions = "TXT" in report_content and "PDF" in report_content
    has_verification = "VERIFY" in report_content or "METADATA" in report_content or "IGNORE" in report_content
    
    if result.get("audit_report_exists"):
        is_recent = (start_time == 0 or report_mtime >= start_time)
        if is_recent and has_extensions and has_verification:
            score += 15
            feedback_parts.append("PASS Audit report exists and contains required sections (+15)")
        elif is_recent:
            score += 7
            feedback_parts.append("PARTIAL Audit report exists but is missing required content sections (+7)")
        else:
            feedback_parts.append("FAIL Audit report exists but pre-dates the task start")
    else:
        feedback_parts.append("FAIL Audit report not found at /home/ga/Reports/filter_audit.txt")

    # ── Determine Pass/Fail ───────────────────────────────────────────────────
    # Passing strictly requires scoring >= 75 AND the out-of-scope files must have been ignored.
    # If the warrant scope constraint is violated (out_ignored == False), it's an automatic failure.
    passed = score >= 75 and out_ignored and (in_scope_hashed > 0 or in_scope_mime > 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }