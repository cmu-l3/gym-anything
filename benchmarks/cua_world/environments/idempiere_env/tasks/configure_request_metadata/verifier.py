#!/usr/bin/env python3
"""
Verifier for configure_request_metadata task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_request_metadata(traj, env_info, task_info):
    """
    Verifies that the 4 CRM metadata records were created correctly.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Get Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Verification Logic
    task_start_time = result.get('task_start_time', 0)
    records = result.get('records', {})
    
    score = 0
    max_score = 100
    feedback = []
    
    # Define items to check
    items = [
        ("request_type", "Request Type 'Design Consultation'"),
        ("request_category", "Request Category 'Plant Selection'"),
        ("request_group", "Request Group 'Design Team'"),
        ("request_resolution", "Request Resolution 'Proposal Accepted'")
    ]
    
    passed_items = 0
    
    for key, label in items:
        item_data = records.get(key, {})
        found = item_data.get('found', False)
        created_epoch = item_data.get('created_epoch', 0)
        
        if not found:
            feedback.append(f"❌ {label} not found in database.")
            continue
            
        # Anti-gaming: Check timestamp
        if created_epoch < task_start_time:
            feedback.append(f"⚠️ {label} exists but was created before task start (Stale Data).")
            # We give 0 points for pre-existing data to strictly enforce "create new"
        else:
            score += 25
            passed_items += 1
            feedback.append(f"✅ {label} created successfully.")

    # 4. Determine Success
    passed = (score >= 100)
    
    final_feedback = "Verification Result: " + " | ".join(feedback)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback
    }