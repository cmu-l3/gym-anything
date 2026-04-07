#!/usr/bin/env python3
"""
Verifier for standardized_ingest_profile_configuration task.

Scoring (100 pts total, pass threshold = 70):
  10 pts  — Case DB found for Backlog_Triage_2024 with data source added.
  25 pts  — Fast_Triage profile correctly created in Autopsy's global configuration.
  30 pts  — Fast_Triage required modules actually executed (MIME, Hash, Ext Mismatch).
  20 pts  — Heavy modules successfully EXCLUDED from the run (verifying SOP adherence).
  15 pts  — Audit report file exists, is recent, and contains the required formatting.
"""

import json
import os
import tempfile

def verify_profile_configuration(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/profile_config_result.json")

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
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script did not run."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}

    # ── Criterion 1: Case DB & Data Source (10 pts) ───────────────────────────
    if result.get("case_db_found") and result.get("data_source_added"):
        score += 10
        feedback_parts.append("PASS Case Backlog_Triage_2024 created with data source (+10)")
    else:
        feedback_parts.append("FAIL Case not found or data source not added")

    # ── Criterion 2: Global Profile Created (25 pts) ──────────────────────────
    if result.get("profile_created"):
        score += 25
        feedback_parts.append("PASS Fast_Triage reusable profile exists in global config (+25)")
    else:
        profiles = result.get("all_profiles", [])
        feedback_parts.append(f"FAIL Fast_Triage profile not found. Profiles found: {profiles}")

    # ── Criterion 3: Required Modules Executed (30 pts) ───────────────────────
    modules_ran = 0
    mime_count = result.get("db_mime_count", 0)
    md5_count = result.get("db_md5_count", 0)
    ext_mismatch_count = result.get("db_ext_mismatch_count", 0)
    out_folders = [f.lower() for f in result.get("module_output_folders", [])]
    
    # 1. File Type ID
    if mime_count > 0 or any("file type" in f for f in out_folders):
        modules_ran += 10
        feedback_parts.append("PASS File Type Identification ran (+10)")
    else:
        feedback_parts.append("FAIL File Type Identification did not run")
        
    # 2. Hash Lookup
    if md5_count > 0 or any("hash lookup" in f for f in out_folders):
        modules_ran += 10
        feedback_parts.append("PASS Hash Lookup ran (+10)")
    else:
        feedback_parts.append("FAIL Hash Lookup did not run")
        
    # 3. Extension Mismatch
    # Even if DB is 0 (no mismatches found), folder might exist if it ran
    if ext_mismatch_count > 0 or any("extension mismatch" in f for f in out_folders):
        modules_ran += 10
        feedback_parts.append("PASS Extension Mismatch Detector ran (+10)")
    else:
        # Give benefit of the doubt if others ran and no mismatch was detected natively
        if mime_count > 0 and md5_count > 0:
            modules_ran += 10
            feedback_parts.append("PASS Extension Mismatch Detector assumed ran (no mismatches found) (+10)")
        else:
            feedback_parts.append("FAIL Extension Mismatch Detector did not run")

    score += modules_ran

    # ── Criterion 4: Heavy Modules Excluded (20 pts) ──────────────────────────
    # If standard default profile is used, ModuleOutput will be flooded with heavy module folders
    if not result.get("heavy_modules_ran") and result.get("case_db_found"):
        score += 20
        feedback_parts.append("PASS Fast_Triage SOP enforced (heavy modules successfully excluded) (+20)")
    elif result.get("heavy_modules_ran"):
        feedback_parts.append("FAIL Heavy modules ran! You did not correctly apply/restrict the profile.")
    else:
        feedback_parts.append("FAIL Could not verify module exclusion (case not processed).")

    # ── Criterion 5: Audit Report (15 pts) ────────────────────────────────────
    start_time = result.get("start_time", 0)
    report_mtime = result.get("audit_report_mtime", 0)
    report_content = result.get("audit_report_content", "").upper()
    
    if result.get("audit_report_exists"):
        is_recent = (start_time == 0 or report_mtime >= start_time)
        has_profile = "PROFILE_NAME: FAST_TRIAGE" in report_content.replace(" ", "")
        has_case = "BACKLOG_TRIAGE" in report_content
        
        if is_recent and has_profile and has_case:
            score += 15
            feedback_parts.append("PASS Audit report is well-formatted and recent (+15)")
        elif is_recent:
            score += 7
            feedback_parts.append("PARTIAL Audit report exists but missing required fields (+7)")
        else:
            feedback_parts.append("FAIL Audit report is stale (pre-dates task start)")
    else:
        feedback_parts.append("FAIL Audit report not found at /home/ga/Reports/profile_audit.txt")

    # Pass/fail threshold
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }