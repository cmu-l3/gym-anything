#!/usr/bin/env python3
"""
Verifier for identify_low_stock_items task.
Checks if the agent correctly identified items with quantity < 20.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_identify_low_stock_items(traj, env_info, task_info):
    """
    Verify the low stock report.
    Criteria:
    1. File exists and was created during task.
    2. Contains correct low stock items.
    3. Does NOT contain high stock items.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_low = [item.lower() for item in metadata.get('expected_low_items', [])]
    expected_high = [item.lower() for item in metadata.get('expected_high_items', [])]

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic Checks
    if not result.get('report_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Report file '/home/ga/low_stock_report.txt' was not created."
        }

    if not result.get('file_created_during_task', False):
         return {
            "passed": False, 
            "score": 0, 
            "feedback": "Report file exists but timestamp indicates it was not created during this task."
        }

    # Content Analysis
    # report_content_raw comes in as comma separated from the bash script tr command
    raw_content = result.get('report_content_raw', "").replace(',', '\n')
    agent_lines = [line.strip().lower() for line in raw_content.split('\n') if line.strip()]
    
    score = 20 # Base points for creating file
    feedback = ["File created."]

    # Check for True Positives (Low Stock Items)
    found_count = 0
    for item in expected_low:
        # Check if the item string appears in any of the agent's lines
        # Using containment to allow for partial matches (e.g. "Amoxicillin" vs "Amoxicillin 500mg")
        if any(item in line or line in item for line in agent_lines):
            found_count += 1
    
    # Points for finding items (20 pts each for 3 items = 60 pts)
    # Scaled if count changes in future
    tp_score = (found_count / len(expected_low)) * 60
    score += tp_score
    feedback.append(f"Identified {found_count}/{len(expected_low)} low stock items.")

    # Check for False Positives (High Stock Items)
    false_positives = 0
    for item in expected_high:
        if any(item in line or line in item for line in agent_lines):
            false_positives += 1
    
    # Deduct or award points for purity (20 pts for perfect exclusion)
    if false_positives == 0:
        score += 20
        feedback.append("Correctly excluded all adequate stock items.")
    else:
        feedback.append(f"Incorrectly included {false_positives} items that have adequate stock.")

    passed = (found_count == len(expected_low)) and (false_positives == 0)

    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback)
    }