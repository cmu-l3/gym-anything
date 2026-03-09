#!/usr/bin/env python3
"""
Verifier for response_data_export@1.

Verifies that the agent successfully exported:
1. Survey responses (CSV) with correct row count and valid content.
2. Survey structure (LSS) with valid XML format.
3. Files were created during the task session.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_response_export(traj, env_info, task_info):
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. CSV Verification (60 points total)
    csv_exists = result.get("csv_exists", False)
    if csv_exists:
        score += 20
        feedback.append("CSV file exists (+20).")
        
        # Check if created during task (Anti-gaming)
        if result.get("csv_created_during_task", False):
            score += 10
            feedback.append("CSV created during task session (+10).")
        else:
            feedback.append("CSV has old timestamp (pre-task?) (0).")
            
        # Check content (Header + 25 rows = 26 lines)
        lines = result.get("csv_lines", 0)
        if lines == 26:
            score += 20
            feedback.append(f"CSV has correct row count ({lines}) (+20).")
        elif lines > 0:
            # Partial credit for getting some data
            score += 5
            feedback.append(f"CSV has incorrect row count ({lines}, expected 26) (+5).")
            
        # Check header
        if result.get("csv_header_valid", False):
            score += 10
            feedback.append("CSV header looks valid (+10).")
        else:
            feedback.append("CSV header missing expected columns (0).")
    else:
        feedback.append("CSV file NOT found (0).")

    # 2. LSS Verification (40 points total)
    lss_exists = result.get("lss_exists", False)
    if lss_exists:
        score += 15
        feedback.append("LSS structure file exists (+15).")
        
        # Anti-gaming
        if result.get("lss_created_during_task", False):
            score += 10
            feedback.append("LSS created during task session (+10).")
        else:
            feedback.append("LSS has old timestamp (0).")
            
        # Structure check
        if result.get("lss_valid_xml", False):
            score += 15
            feedback.append("LSS file is valid XML (+15).")
        else:
            feedback.append("LSS file is not valid XML (0).")
    else:
        feedback.append("LSS structure file NOT found (0).")

    # Pass logic
    # Must have at least CSV file with some data to pass at all
    # Threshold 70
    passed = (score >= 70) and csv_exists and (result.get("csv_lines", 0) > 1)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }