#!/usr/bin/env python3
"""
Verifier for error_log_harvesting_and_triage task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_error_log_harvesting(traj, env_info, task_info):
    """
    Verifies that error logs were extracted to text files and emails were moved.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    min_files = metadata.get('min_files', 3)

    # 2. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 3. Score Calculation
    score = 0
    feedback = []

    # Criterion A: Local Directory Created (10 pts)
    if result.get("logs_dir_exists", False):
        score += 10
        feedback.append("Directory ~/Documents/ErrorLogs created.")
    else:
        feedback.append("Directory ~/Documents/ErrorLogs NOT found.")

    # Criterion B: BlueMail Folder Created (10 pts)
    if result.get("processed_folder_exists", False):
        score += 10
        feedback.append("BlueMail folder 'Processed-Logs' created.")
    else:
        feedback.append("BlueMail folder 'Processed-Logs' NOT found.")

    # Criterion C: Files Created (20 pts)
    file_count = result.get("file_count", 0)
    if file_count >= min_files:
        score += 20
        feedback.append(f"Created {file_count} log files (Target: {min_files}).")
    elif file_count > 0:
        score += 10
        feedback.append(f"Created {file_count} log files (Target: {min_files}) - Partial points.")
    else:
        feedback.append("No log files created.")

    # Criterion D: Content Validity (30 pts)
    # Checks if extracted text actually exists in emails
    valid_files = 0
    moved_correctly = 0
    verifications = result.get("content_verification", [])
    
    for v in verifications:
        if v["valid_source"]:
            valid_files += 1
            if v["location_found"] == "Processed-Logs":
                moved_correctly += 1
    
    # Score for validity
    if valid_files >= min_files:
        score += 30
        feedback.append("All extracted logs matched source emails.")
    elif valid_files > 0:
        # Prorated
        points = int((valid_files / min_files) * 30)
        score += points
        feedback.append(f"Only {valid_files} logs matched source emails.")
    else:
        feedback.append("Extracted content did not match any source emails (hallucination check).")

    # Criterion E: Emails Archived (20 pts)
    # Checks if the emails corresponding to the logs were actually moved
    if moved_correctly >= min_files:
        score += 20
        feedback.append("Source emails were correctly moved to Processed-Logs.")
    elif moved_correctly > 0:
        points = int((moved_correctly / min_files) * 20)
        score += points
        feedback.append(f"Only {moved_correctly} source emails were correctly moved.")
    else:
        feedback.append("Source emails were NOT found in Processed-Logs.")

    # Criterion F: Filesystem Cleanliness (10 pts)
    if result.get("clean_root_docs", True):
        score += 10
        feedback.append("Documents root is clean.")
    else:
        feedback.append("Files found in Documents root (should be in ErrorLogs).")

    # 4. Final Verdict
    # Threshold 70 points
    passed = score >= 70 and file_count >= 1

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }