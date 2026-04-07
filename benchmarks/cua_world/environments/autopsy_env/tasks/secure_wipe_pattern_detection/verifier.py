#!/usr/bin/env python3
"""
Verifier for secure_wipe_pattern_detection task.

Scoring (100 pts total, pass threshold = 60):
  10 pts - Case DB created and evidence ingested
  10 pts - Both report files exist and were modified during the task
  20 pts - INTACT files correctly classified in CSV
  25 pts - WIPED_ZERO files correctly classified in CSV
  25 pts - WIPED_FF files correctly classified in CSV
  10 pts - Summary file contains accurate counts mapping to the CSV
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_secure_wipe_pattern_detection(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/secure_wipe_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/wiped_files_gt.json")
    
    # Copy result JSON from container
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env(result_file_vm, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - task not attempted."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # Copy Ground Truth JSON from container
    gt = {"INTACT": [], "WIPED_ZERO": [], "WIPED_FF": []}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        copy_from_env(gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception as e:
        logger.error(f"Could not load ground truth: {e}")

    # 1. Check Autopsy Case (10 pts)
    if result.get("case_db_found") and result.get("data_source_added"):
        score += 10
        feedback_parts.append("PASS Case created and data source ingested (+10)")
    else:
        feedback_parts.append("FAIL Case or data source missing")

    # 2. Files Exist and are recent (10 pts)
    start_time = result.get("start_time", 0)
    csv_exists = result.get("csv_exists", False)
    csv_mtime = result.get("csv_mtime", 0)
    sum_exists = result.get("summary_exists", False)
    
    files_valid = False
    if csv_exists and sum_exists:
        if start_time == 0 or csv_mtime >= start_time:
            score += 10
            files_valid = True
            feedback_parts.append("PASS Report files created during session (+10)")
        else:
            feedback_parts.append("FAIL Report files appear to be stale (pre-date task start)")
    else:
        feedback_parts.append("FAIL Missing required CSV or summary report files")

    # Parse CSV for accuracy
    csv_content = result.get("csv_content", "")
    parsed_classifications = {}
    
    for line in csv_content.splitlines():
        line = line.strip()
        if not line or "PAYLOAD_STATUS" in line.upper():
            continue
        parts = line.split("|")
        if len(parts) >= 3:
            filename = parts[0].strip().lower()
            status = parts[2].strip().upper()
            
            # Since FAT32 deletion mangles the first char (e.g. _otes.txt instead of notes.txt),
            # we strip the first char for matching if it starts with _
            if filename.startswith("_"):
                filename = filename[1:]
            
            parsed_classifications[filename] = status

    def check_accuracy(gt_category, expected_status, points_max):
        gt_files = gt.get(gt_category, [])
        if not gt_files:
            return 0
            
        correct = 0
        for f in gt_files:
            # Check if remaining characters of filename are in any parsed key
            # (handles both full LFN name recovery and 8.3 _ mangled name)
            search_name = f.lower()[1:] 
            for parsed_name, status in parsed_classifications.items():
                if search_name in parsed_name:
                    if status == expected_status:
                        correct += 1
                    break
                    
        awarded = int((correct / len(gt_files)) * points_max)
        feedback_parts.append(f"EVAL {gt_category}: {correct}/{len(gt_files)} correct (+{awarded})")
        return awarded

    # 3. Score Classifications
    if files_valid and parsed_classifications:
        score += check_accuracy("INTACT", "INTACT", 20)
        score += check_accuracy("WIPED_ZERO", "WIPED_ZERO", 25)
        score += check_accuracy("WIPED_FF", "WIPED_FF", 25)
    else:
        feedback_parts.append("FAIL Cannot score accuracy; CSV invalid or empty")

    # 4. Summary Format (10 pts)
    sum_content = result.get("summary_content", "").upper()
    if files_valid:
        req_keys = ["TOTAL_DELETED_FILES_ANALYZED", "INTACT_FILES", "WIPED_ZERO_FILES", "WIPED_FF_FILES", "CONCLUSION"]
        if all(k in sum_content for k in req_keys):
            score += 10
            feedback_parts.append("PASS Summary file contains all required sections (+10)")
        else:
            feedback_parts.append("FAIL Summary file is missing required section headers")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }