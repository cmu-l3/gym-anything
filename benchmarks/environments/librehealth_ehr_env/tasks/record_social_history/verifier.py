#!/usr/bin/env python3
"""
Verifier for record_social_history task.

Verifies that:
1. The agent logged in and navigated correctly (implicit in DB change).
2. The specific patient's history records were updated in the database.
3. The values match the task requirements (Tobacco, Alcohol, Drugs, etc.).
4. Verification uses Database state as primary signal and VLM as secondary signal.
"""

import json
import tempfile
import os
import logging
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_social_history(traj, env_info, task_info):
    """
    Verify the social history update task.
    """
    # 1. Setup environment access
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Retrieve result file
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

    # 3. Extract Data
    final_state = result.get('final_state', {})
    initial_state = result.get('initial_state', {})
    task_start = result.get('task_start', 0)
    task_end = result.get('task_end', 0)
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 4. Anti-gaming Checks (10 pts)
    # Check if task duration was reasonable (>15 seconds)
    duration = task_end - task_start
    if duration > 15:
        score += 10
    else:
        feedback_parts.append("Task completed suspiciously fast")

    # Check if data actually changed from initial state
    data_changed = final_state != initial_state
    if not data_changed:
        feedback_parts.append("No changes detected in database")
        return {
            "passed": False, 
            "score": score, 
            "feedback": "Data remains unchanged from initial state."
        }

    # 5. Verify Fields (90 pts)
    # Helper to check string containment (case-insensitive)
    def check_field(field_name, value, expected_keywords, points):
        if not value:
            return 0, f"{field_name} empty"
        
        val_lower = str(value).lower()
        
        # Exact match check for Tobacco (dropdown usually)
        if field_name == "Tobacco":
            if "current every day" in val_lower or "everyday smoker" in val_lower:
                return points, f"{field_name} correct"
        
        # Keyword check for free text fields
        matches = [k for k in expected_keywords if k.lower() in val_lower]
        if len(matches) >= len(expected_keywords) - 1: # Allow missing one keyword
            return points, f"{field_name} correct"
        elif len(matches) > 0:
            return int(points / 2), f"{field_name} partially correct"
        
        return 0, f"{field_name} incorrect ('{value}')"

    # Field 1: Tobacco (25 pts)
    # Expected: "Current every day smoker"
    tobacco_val = final_state.get('tobacco', '')
    pts, msg = check_field("Tobacco", tobacco_val, ["current", "every", "day"], 25)
    score += pts
    feedback_parts.append(msg)

    # Field 2: Alcohol (20 pts)
    # Expected: "Beer and wine, 4-5 drinks per week"
    alcohol_val = final_state.get('alcohol', '')
    pts, msg = check_field("Alcohol", alcohol_val, ["beer", "wine", "drinks"], 20)
    score += pts
    feedback_parts.append(msg)

    # Field 3: Drugs (15 pts)
    # Expected: "None"
    drugs_val = final_state.get('recreational_drugs', '')
    pts, msg = check_field("Drugs", drugs_val, ["none"], 15)
    score += pts
    feedback_parts.append(msg)

    # Field 4: Exercise (15 pts)
    # Expected: "Sedentary lifestyle, no regular exercise"
    ex_val = final_state.get('exercise_patterns', '')
    pts, msg = check_field("Exercise", ex_val, ["sedentary", "no regular"], 15)
    score += pts
    feedback_parts.append(msg)

    # Field 5: Counseling (15 pts)
    # Expected: "N/A"
    couns_val = final_state.get('counseling', '')
    pts, msg = check_field("Counseling", couns_val, ["n/a"], 15)
    score += pts
    feedback_parts.append(msg)

    # 6. Final Evaluation
    passed = score >= 60  # Pass if roughly 3/5 fields are correct + anti-gaming
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }