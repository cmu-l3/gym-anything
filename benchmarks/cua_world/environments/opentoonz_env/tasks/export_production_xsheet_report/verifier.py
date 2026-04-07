#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_production_xsheet_report(traj, env_info, task_info):
    """
    Verify that the Xsheet was exported as HTML with the renamed column.
    
    Scoring:
    - HTML File Exists: 30 pts
    - Correct Column Name ("HERO_WALK_V1"): 40 pts
    - Valid HTML Format: 20 pts
    - New File (Anti-gaming): 10 pts
    
    Pass Threshold: 70 pts
    """
    
    # 1. Setup and retrieve result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # 2. Extract metrics
    file_exists = result.get('file_exists', False)
    contains_target_string = result.get('contains_target_string', False)
    is_valid_html = result.get('is_valid_html', False)
    file_created_during_task = result.get('file_created_during_task', False)
    
    score = 0
    feedback = []

    # 3. Score calculation
    
    # Criterion 1: File Exists (30 pts)
    if file_exists:
        score += 30
        feedback.append("Output HTML file found.")
    else:
        feedback.append("Output HTML file NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: Correct Column Name (40 pts)
    if contains_target_string:
        score += 40
        feedback.append("Column successfully renamed to 'HERO_WALK_V1' in report.")
    else:
        feedback.append("Report does NOT contain expected column name 'HERO_WALK_V1'.")

    # Criterion 3: Valid HTML (20 pts)
    if is_valid_html:
        score += 20
        feedback.append("File is valid HTML.")
    else:
        feedback.append("File is not valid HTML format.")

    # Criterion 4: Freshness (10 pts)
    if file_created_during_task:
        score += 10
        feedback.append("File was created during the task.")
    else:
        feedback.append("File timestamp indicates it was not created during this task.")

    # 4. Final Result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }