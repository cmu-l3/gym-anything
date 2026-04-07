#!/usr/bin/env python3
"""
Verifier for copy_session_identification task.

Scoring (100 pts total, pass threshold = 60):
  10 pts  - Case DB exists with correct name
  10 pts  - Disk image added as data source
  10 pts  - Ingest completed
  10 pts  - Session report exists and is recent
  10 pts  - Total file count within tolerance
  10 pts  - Session count within tolerance
  15 pts  - File name coverage >= 50%
  10 pts  - Report has valid SESSION/FILE structure
  10 pts  - Summary has all required fields
   5 pts  - Largest session count accurate
"""

import json
import os
import re
import tempfile

def verify_copy_session_identification(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/copy_session_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/copy_session_gt.json")

    # 1. Retrieve the exported JSON result
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
            "feedback": "Result file not found - task was not attempted."
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # 2. Retrieve Ground Truth JSON
    gt = {"total_files": 0, "total_sessions": 0, "largest_session": 0, "file_names": []}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        env_info["copy_from_env"](gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        pass

    gt_total_files = gt.get("total_files", 0)
    gt_total_sessions = gt.get("total_sessions", 0)
    gt_largest_session = gt.get("largest_session", 0)
    gt_names = set(n.lower() for n in gt.get("file_names", []))

    # --- Autopsy DB State Checks ---
    
    if result.get("case_db_found"):
        score += 10
        feedback_parts.append("PASS Case DB found (+10)")
    else:
        feedback_parts.append("FAIL Case DB not found")

    if result.get("data_source_added"):
        score += 10
        feedback_parts.append("PASS Data source added (+10)")
    else:
        feedback_parts.append("FAIL Data source not found in DB")

    if result.get("ingest_completed"):
        score += 10
        feedback_parts.append("PASS Ingest completed (+10)")
    else:
        feedback_parts.append("FAIL Ingest did not complete")

    # --- Report Analysis ---
    start_time = result.get("start_time", 0)
    report_exists = result.get("report_file_exists", False)
    report_mtime = result.get("report_mtime", 0)
    report_content = result.get("report_content", "")
    
    summary_exists = result.get("summary_file_exists", False)
    summary_content = result.get("summary_content", "")

    if report_exists:
        if start_time == 0 or report_mtime >= start_time:
            score += 10
            feedback_parts.append("PASS Report file exists and is recent (+10)")
        else:
            score += 5
            feedback_parts.append("PARTIAL Report file exists but is stale (+5)")
    else:
        feedback_parts.append("FAIL Report file missing")

    if report_exists and report_content:
        # Extract metrics using regex
        total_files_match = re.search(r'TOTAL_FILES_ANALYZED:\s*(\d+)', report_content, re.IGNORECASE)
        total_sessions_match = re.search(r'TOTAL_SESSIONS:\s*(\d+)', report_content, re.IGNORECASE)
        largest_match = re.search(r'LARGEST_SESSION_FILE_COUNT:\s*(\d+)', report_content, re.IGNORECASE)

        # File count tolerance (± 20%)
        if total_files_match:
            val = int(total_files_match.group(1))
            if gt_total_files > 0 and abs(val - gt_total_files) <= (0.2 * gt_total_files):
                score += 10
                feedback_parts.append(f"PASS Reported files {val} within tolerance (+10)")
            else:
                feedback_parts.append(f"FAIL Reported files {val} outside tolerance of {gt_total_files}")
        else:
            feedback_parts.append("FAIL Missing TOTAL_FILES_ANALYZED header")

        # Session count tolerance (± 2)
        if total_sessions_match:
            val = int(total_sessions_match.group(1))
            if abs(val - gt_total_sessions) <= 2:
                score += 10
                feedback_parts.append(f"PASS Reported sessions {val} matches GT (+10)")
            else:
                feedback_parts.append(f"FAIL Reported sessions {val} outside tolerance of {gt_total_sessions}")
        else:
            feedback_parts.append("FAIL Missing TOTAL_SESSIONS header")

        # Largest session size tolerance (± 2)
        if largest_match:
            val = int(largest_match.group(1))
            if abs(val - gt_largest_session) <= 2:
                score += 5
                feedback_parts.append(f"PASS Largest session size {val} matches GT (+5)")
            else:
                feedback_parts.append(f"FAIL Largest session size {val} outside tolerance of {gt_largest_session}")
        else:
            feedback_parts.append("FAIL Missing LARGEST_SESSION_FILE_COUNT header")

        # File name coverage
        if gt_names:
            report_lower = report_content.lower()
            matched = sum(1 for name in gt_names if name in report_lower)
            coverage = matched / len(gt_names)
            if coverage >= 0.5:
                score += 15
                feedback_parts.append(f"PASS GT filename coverage {coverage*100:.0f}% (+15)")
            elif coverage >= 0.2:
                score += 7
                feedback_parts.append(f"PARTIAL GT filename coverage {coverage*100:.0f}% (+7)")
            else:
                feedback_parts.append(f"FAIL Low GT filename coverage {coverage*100:.0f}%")
        
        # Structure verification
        has_session_blocks = bool(re.search(r'SESSION\s+\d+:', report_content, re.IGNORECASE))
        has_file_entries = bool(re.search(r'FILE:\s+.*\|', report_content, re.IGNORECASE))
        if has_session_blocks and has_file_entries:
            score += 10
            feedback_parts.append("PASS Correct SESSION/FILE block structure (+10)")
        elif has_session_blocks or has_file_entries:
            score += 5
            feedback_parts.append("PARTIAL Partial SESSION/FILE structure (+5)")
        else:
            feedback_parts.append("FAIL Missing required SESSION/FILE block format")

    # --- Summary Analysis ---
    if summary_exists and summary_content:
        required_summary_fields = [
            "INVESTIGATION_SUBJECT",
            "TOTAL_COPY_SESSIONS",
            "SINGLE_FILE_SESSIONS",
            "MULTI_FILE_SESSIONS",
            "LARGEST_SESSION",
            "CONCLUSION"
        ]
        
        fields_found = sum(1 for f in required_summary_fields if f in summary_content)
        if fields_found == len(required_summary_fields):
            score += 10
            feedback_parts.append("PASS Summary has all required fields (+10)")
        elif fields_found >= 3:
            score += 5
            feedback_parts.append(f"PARTIAL Summary has {fields_found}/{len(required_summary_fields)} fields (+5)")
        else:
            feedback_parts.append("FAIL Summary missing most required fields")
    else:
        feedback_parts.append("FAIL Summary file missing or empty")

    passed = score >= 60 and result.get("case_db_found", False) and report_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }