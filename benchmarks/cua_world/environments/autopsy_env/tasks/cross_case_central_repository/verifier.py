#!/usr/bin/env python3
"""
Verifier for cross_case_central_repository task.

Scoring (100 pts total, pass threshold = 70):
  20 pts  — Central Repository SQLite database created and populated
  20 pts  — Both cases (Operation_Alpha and Operation_Beta) registered in the CR DB
  15 pts  — Correlation instances recorded in CR DB (proving Correlation Engine ran)
  15 pts  — Report file exists and is written after the task starts
  30 pts  — Report correctly identifies the dynamically generated MD5 and BOTH filenames
"""

import json
import os
import re
import tempfile

def verify_cross_case_central_repository(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/cross_case_result.json")

    # ── Pull result JSON from VM ──────────────────────────────────────────────
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        
        copy_from_env = env_info.get("copy_from_env")
        if not copy_from_env:
            return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available."}
            
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

    # ── Verify Variables ──────────────────────────────────────────────────────
    start_time = result.get("start_time", 0)
    shared_md5 = result.get("shared_md5", "").lower()
    report_content = result.get("report_content", "").replace("\\n", "\n")
    report_mtime = result.get("report_mtime", 0)
    
    # Expected filenames based on setup_task.sh
    filename_alpha = "financial_records.pdf"
    filename_beta = "stolen_financials.pdf"

    # ── Criterion 1: Central Repo Configured (20 pts) ─────────────────────────
    if result.get("cr_db_found"):
        score += 20
        feedback_parts.append("PASS Central Repository DB exists and is formatted correctly (+20)")
    else:
        feedback_parts.append("FAIL Central Repository DB not found or missing required schema")

    # ── Criterion 2: Both Cases Registered in CR (20 pts) ─────────────────────
    cases_count = result.get("cr_cases_count", 0)
    cases_names = [n.lower() for n in result.get("cr_cases_names", [])]
    
    alpha_found = any("alpha" in n for n in cases_names)
    beta_found = any("beta" in n for n in cases_names)

    if cases_count >= 2 and alpha_found and beta_found:
        score += 20
        feedback_parts.append(f"PASS Both Operation_Alpha and Operation_Beta registered in CR (+20)")
    elif cases_count >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL Only {cases_count} case(s) found in CR DB (+10)")
    else:
        feedback_parts.append("FAIL No cases registered in Central Repository DB")

    # ── Criterion 3: Correlation Engine Populated (15 pts) ────────────────────
    instances = result.get("cr_instances_count", 0)
    if instances > 0:
        score += 15
        feedback_parts.append(f"PASS Correlation instances populated in CR DB: {instances} items (+15)")
    else:
        feedback_parts.append("FAIL No correlation instances found in CR DB (Correlation Engine may not have run)")

    # ── Criterion 4: Report File Exists & is Recent (15 pts) ──────────────────
    if result.get("report_file_exists"):
        if start_time == 0 or report_mtime >= start_time:
            score += 15
            feedback_parts.append("PASS Report file exists and was written during the task (+15)")
        else:
            score += 5
            feedback_parts.append("PARTIAL Report file exists but appears stale (timestamp predates task) (+5)")
    else:
        feedback_parts.append("FAIL Report file not found at /home/ga/Reports/cross_case_intelligence.txt")

    # ── Criterion 5: Accurate Match Identification (30 pts) ───────────────────
    if result.get("report_file_exists") and report_content.strip():
        report_lower = report_content.lower()
        
        has_md5 = shared_md5 in report_lower if shared_md5 else False
        has_alpha_name = filename_alpha.lower() in report_lower
        has_beta_name = filename_beta.lower() in report_lower
        
        if has_md5 and has_alpha_name and has_beta_name:
            score += 30
            feedback_parts.append("PASS Report correctly identifies the dynamic MD5 and BOTH distinct filenames (+30)")
        elif has_md5 and (has_alpha_name or has_beta_name):
            score += 20
            feedback_parts.append("PARTIAL Report identifies the correct MD5 but is missing one of the filenames (+20)")
        elif has_md5:
            score += 15
            feedback_parts.append("PARTIAL Report identifies the correct MD5 but is missing both filenames (+15)")
        elif has_alpha_name and has_beta_name:
            # They found the files but didn't write the MD5 correctly
            score += 10
            feedback_parts.append("PARTIAL Report contains the filenames but missing the correct MD5 hash (+10)")
        else:
            feedback_parts.append("FAIL Report does not contain the target MD5 or filenames")
    else:
        feedback_parts.append("FAIL Report file is empty or missing")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }