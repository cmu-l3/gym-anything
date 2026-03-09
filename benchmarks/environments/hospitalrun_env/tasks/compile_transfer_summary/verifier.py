#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compile_transfer_summary(traj, env_info, task_info):
    """
    Verifies that the agent created a text summary for Patient Walter Bishop containing:
    - Active Meds: Digoxin, Warfarin
    - Allergies: Penicillin, Strawberries
    - EXCLUDED: Amoxicillin (Completed med)
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_strings = metadata.get('required_strings', [])
    forbidden_strings = metadata.get('forbidden_strings', [])

    # 2. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Basic Validation (File Existence)
    if not result.get('output_exists'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "The file '/home/ga/transfer_summary.txt' was not found."
        }

    # 4. Anti-Gaming Check (Timestamp)
    task_start = result.get('task_start', 0)
    file_mtime = result.get('file_mtime', 0)
    if file_mtime < task_start:
        return {
            "passed": False,
            "score": 0,
            "feedback": "The output file appears to be created before the task started."
        }

    # 5. Content Analysis
    content = result.get('output_content', '').lower()
    score = 10 # Base points for creating the file
    feedback_items = ["File created"]

    # Check Required Strings (20 pts each for 4 items = 80 pts potential)
    # Using 18 pts each to allow room for exclusion bonus
    missed_items = []
    found_items = []
    
    item_points = 15
    
    for item in required_strings:
        if item.lower() in content:
            score += item_points
            found_items.append(item)
        else:
            missed_items.append(item)

    # Check Forbidden Strings (20 pts)
    # The agent successfully FILTERED out the inactive med
    forbidden_hit = False
    for item in forbidden_strings:
        if item.lower() in content:
            forbidden_hit = True
            feedback_items.append(f"FAILED: Included inactive medication '{item}'")
            score -= 10 # Penalty for including wrong info
        else:
            score += 20 # Bonus for correct filtering
            feedback_items.append(f"Correctly excluded '{item}'")

    if found_items:
        feedback_items.append(f"Found: {', '.join(found_items)}")
    if missed_items:
        feedback_items.append(f"Missing: {', '.join(missed_items)}")

    # 6. Final Scoring Logic
    # Pass threshold: 70
    # Must have found at least 3 required items and NOT included the forbidden one to pass reliably
    
    passed = (score >= 70) and (not forbidden_hit) and (len(found_items) >= 3)

    return {
        "passed": passed,
        "score": max(0, min(100, score)),
        "feedback": " | ".join(feedback_items)
    }