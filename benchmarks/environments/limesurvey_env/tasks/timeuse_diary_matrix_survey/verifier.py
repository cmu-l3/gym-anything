#!/usr/bin/env python3
"""
Verifier for timeuse_diary_matrix_survey task.

Criteria:
1. Survey exists with correct title (Gate)
2. Survey has 3 groups
3. Contains Array (Numbers) question
4. Correct dimensions (Rows >= 8, Cols = 7)
5. Validation set (Min 0, Max 24)
6. Survey is active
7. Format is Group-by-group
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_timeuse_diary_matrix_survey(traj, env_info, task_info):
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment error: copy unavailable"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_y_min = metadata.get('expected_yaxis_count_min', 8)
    expected_x = metadata.get('expected_xaxis_count', 7)
    
    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring
    score = 0
    feedback = []
    
    # 1. Gate: Survey Exists
    if not result.get("survey_found"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No survey found with title containing 'Time Allocation' or 'Student Life'"
        }
    feedback.append("Survey found")
    
    # 2. Structure: 3 Groups (15 pts)
    g_count = result.get("group_count", 0)
    if g_count >= 3:
        score += 15
        feedback.append("Correct number of groups (3+)")
    else:
        feedback.append(f"Insufficient groups found: {g_count}/3")

    # 3. Question Type: Array Numbers (20 pts)
    if result.get("question_found"):
        score += 20
        feedback.append("Array (Numbers) question found")
        
        # 4. Dimensions (30 pts split)
        # Y-axis (Rows)
        y_count = result.get("y_axis_count", 0)
        if y_count >= expected_y_min:
            score += 15
            feedback.append(f"Activity rows correct ({y_count})")
        else:
            feedback.append(f"Not enough activity rows ({y_count}/{expected_y_min})")
            
        # X-axis (Cols)
        x_count = result.get("x_axis_count", 0)
        if x_count == expected_x:
            score += 15
            feedback.append("Day columns correct (7)")
        else:
            feedback.append(f"Incorrect day columns ({x_count}/7)")
            
        # 5. Validation (10 pts)
        min_v = result.get("min_val", "")
        max_v = result.get("max_val", "")
        
        # Handle string/int comparison loosely
        if str(min_v).strip() == "0":
            score += 5
        else:
            feedback.append(f"Min value incorrect ({min_v})")
            
        if str(max_v).strip() == "24":
            score += 5
        else:
            feedback.append(f"Max value incorrect ({max_v})")
            
    else:
        feedback.append("Array (Numbers) question NOT found")

    # 6. Active Status (15 pts)
    if result.get("active") == "Y":
        score += 15
        feedback.append("Survey is active")
    else:
        feedback.append("Survey is NOT active")

    # 7. Format (10 pts)
    # LimeSurvey stores format as 'G' for Group-by-group
    if result.get("format") == "G":
        score += 10
        feedback.append("Format is Group-by-group")
    else:
        feedback.append(f"Format incorrect ({result.get('format')})")

    # Final tally
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }