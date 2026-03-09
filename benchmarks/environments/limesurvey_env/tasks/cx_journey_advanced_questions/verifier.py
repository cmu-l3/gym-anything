#!/usr/bin/env python3
"""
Verifier for Customer Experience Journey Survey Task
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cx_survey(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/cx_journey_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Gate Check: Survey Found (0 pts, prerequisite)
    if not result.get('found'):
        return {"passed": False, "score": 0, "feedback": "Survey 'Customer Experience Journey Survey Q4 2024' not found."}

    # Anti-gaming: Check creation time
    created_str = result.get('date_created', '')
    task_start = result.get('task_start_time', 0)
    try:
        # LimeSurvey format usually 'YYYY-MM-DD HH:MM:SS'
        created_ts = datetime.strptime(created_str, "%Y-%m-%d %H:%M:%S").timestamp()
        if created_ts < task_start:
             return {"passed": False, "score": 0, "feedback": "Survey appears to have been created before the task started."}
    except:
        pass # If parsing fails, lenient fallthrough or log warning

    feedback.append("Survey found.")

    # 2. Messages (20 pts)
    # Welcome
    if "Customer Experience study" in result.get('welcome', ''):
        score += 10
        feedback.append("Welcome message correct.")
    else:
        feedback.append("Welcome message missing required text.")
        
    # End text
    if "feedback helps us improve" in result.get('endtext', ''):
        score += 10
        feedback.append("End message correct.")
    else:
        feedback.append("End message missing required text.")

    # 3. Groups (10 pts)
    if result.get('groups_count', 0) == 3:
        score += 10
        feedback.append("Correct number of question groups (3).")
    else:
        feedback.append(f"Incorrect number of groups: {result.get('groups_count')}. Expected 3.")

    # 4. Questions Verification
    questions = result.get('questions', [])
    
    # Check Q1: Date (Type D) (10 pts)
    q1 = next((q for q in questions if q.get('type') == 'D'), None)
    if q1:
        score += 10
        feedback.append("Date question found.")
    else:
        feedback.append("Date question (Type D) not found.")

    # Check Q2: Numerical (Type N) + Validation (8 + 12 = 20 pts)
    q2 = next((q for q in questions if q.get('type') == 'N'), None)
    if q2:
        score += 8
        feedback.append("Numerical question found.")
        min_v = q2.get('min_val', '')
        max_v = q2.get('max_val', '')
        if str(min_v) == '1' and str(max_v) == '10000':
            score += 12
            feedback.append("Numerical validation correct (1-10000).")
        else:
            feedback.append(f"Numerical validation incorrect or missing. Found min={min_v}, max={max_v}.")
    else:
        feedback.append("Numerical question (Type N) not found.")

    # Check Q3: Array (Type F, H, A, etc) with >= 5 subs (10 pts)
    # LimeSurvey array types: F (Array), H (Array by column), 1 (Array dual), A (Array 5 point), etc.
    q3 = next((q for q in questions if q.get('type') in ['F', 'H', '1', 'A', 'B', 'C', 'E', ':']), None)
    if q3:
        if q3.get('sub_count', 0) >= 5:
            score += 10
            feedback.append("Array question with >=5 subquestions found.")
        else:
            feedback.append("Array question found but insufficient subquestions.")
    else:
        feedback.append("Array question not found.")

    # Check Q4: Ranking (Type R) with >= 5 items (10 pts)
    q4 = next((q for q in questions if q.get('type') == 'R'), None)
    if q4:
        if q4.get('sub_count', 0) >= 5:
            score += 10
            feedback.append("Ranking question with >=5 items found.")
        else:
            feedback.append("Ranking question found but insufficient items.")
    else:
        feedback.append("Ranking question (Type R) not found.")

    # Check Q5: Multiple Choice (Type M) with >= 5 items (10 pts)
    q5 = next((q for q in questions if q.get('type') == 'M'), None)
    if q5:
        if q5.get('sub_count', 0) >= 5:
            score += 10
            feedback.append("Multiple Choice question with >=5 items found.")
        else:
            feedback.append("Multiple Choice question found but insufficient items.")
    else:
        feedback.append("Multiple Choice question (Type M) not found.")

    # 5. Activation (10 pts)
    if str(result.get('active', '')).upper() == 'Y':
        score += 10
        feedback.append("Survey is active.")
    else:
        feedback.append("Survey is NOT active.")

    passed = (score >= 70) and result.get('found')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }