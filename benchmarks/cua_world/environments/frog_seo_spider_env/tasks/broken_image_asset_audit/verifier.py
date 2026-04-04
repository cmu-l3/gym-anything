#!/usr/bin/env python3
"""
Verifier for Broken Image Asset Audit Task
"""

import json
import os
import tempfile
import logging
import csv

logger = logging.getLogger(__name__)

def verify_broken_image_asset_audit(traj, env_info, task_info):
    """
    Verifies that the agent exported a report of broken images (4xx) from the target site.
    
    Scoring Criteria:
    1. Valid Export File Created (30 pts)
       - File exists, created during task, contains data.
    2. Content Verification (70 pts)
       - Contains Image URLs (40 pts)
       - Contains 4xx Status Codes (30 pts)
       
    Penalties:
    - Wrong domain (fail)
    - Empty file (fail)
    """
    
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    # Load result JSON from container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Evaluate Criteria
    score = 0
    feedback = []
    
    # Criterion 1: Export File Existence (30 pts)
    file_created = result.get('file_created', False)
    row_count = result.get('row_count', 0)
    
    if file_created and row_count > 0:
        score += 30
        feedback.append("Success: Export file created with data.")
    elif file_created:
        # File exists but is empty
        score += 10
        feedback.append("Partial: Export file created but appears empty.")
    else:
        feedback.append("Fail: No export file created during the task.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: Domain Check (Critical)
    found_domain = result.get('found_crawler_test', False)
    if not found_domain:
        feedback.append("Fail: Exported data does not appear to be from 'crawler-test.com'.")
        # Start deducting or cap score
        return {"passed": False, "score": 10, "feedback": " ".join(feedback)}
    else:
        feedback.append("Verified: Data corresponds to target domain.")

    # Criterion 3: Image Assets (40 pts)
    is_image_report = result.get('is_image_report', False)
    if is_image_report:
        score += 40
        feedback.append("Success: Export contains image URLs.")
    else:
        feedback.append("Fail: Export does not appear to contain image assets (no .jpg, .png, etc found).")

    # Criterion 4: Status Codes (30 pts)
    has_4xx = result.get('has_4xx_errors', False)
    if has_4xx:
        score += 30
        feedback.append("Success: Export contains 4xx/Client Error status codes.")
    else:
        feedback.append("Fail: Export does not contain 4xx error codes.")

    # 3. Final Assessment
    passed = score >= 70
    
    # Bonus/Sanity Check: App was running
    if result.get('app_running', False):
        feedback.append("(App was running correctly).")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }