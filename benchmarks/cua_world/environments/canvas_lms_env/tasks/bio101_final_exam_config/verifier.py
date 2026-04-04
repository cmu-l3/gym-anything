#!/usr/bin/env python3
"""
Verifier for bio101_final_exam_config task.

Verifies:
1. Quiz creation in correct course
2. Specific administrative settings (time limit, attempts, access code)
3. Dates (Due, Available From/To) relative to task execution time
4. Publication state
"""

import json
import tempfile
import os
import logging
from datetime import datetime, timedelta, timezone

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_canvas_date(date_str):
    """Parses Canvas DB timestamp format (YYYY-MM-DD HH:MM:SS.xxxxxx)."""
    if not date_str or date_str == 'None' or date_str == '':
        return None
    # Canvas DB dates in export might look like "2026-03-24 05:00:00" or contain T/Z
    clean_str = date_str.replace('T', ' ').replace('Z', '')
    # Truncate fractional seconds if present
    if '.' in clean_str:
        clean_str = clean_str.split('.')[0]
    
    try:
        return datetime.strptime(clean_str, "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
    except ValueError:
        return None

def verify_bio101_final_exam_config(traj, env_info, task_info):
    """
    Verify that the final exam quiz was configured correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic checks
    if not result.get('quiz_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No quiz found. The quiz 'BIO101 Final Examination' was not created in the BIO101 course."
        }

    quiz = result['quiz']
    score = 0
    feedback = []
    
    # Metadata targets
    meta = task_info.get('metadata', {})
    target_title = meta.get('target_quiz_title', "BIO101 Final Examination")
    
    # 1. Existence and Title (15 pts)
    if quiz.get('title', '').strip().lower() == target_title.lower():
        score += 15
        feedback.append("Quiz created with correct title.")
    else:
        feedback.append(f"Incorrect title. Expected '{target_title}', found '{quiz.get('title')}'")

    # 2. Quiz Type (10 pts)
    # Canvas DB stores graded quizzes as 'assignment'
    if quiz.get('quiz_type') == 'assignment':
        score += 10
        feedback.append("Correct quiz type (Graded Quiz).")
    else:
        feedback.append(f"Incorrect quiz type. Expected 'assignment' (Graded Quiz), found '{quiz.get('quiz_type')}'")

    # 3. Time Limit (10 pts)
    try:
        if int(float(quiz.get('time_limit', 0))) == 90:
            score += 10
            feedback.append("Time limit correct (90 min).")
        else:
            feedback.append(f"Incorrect time limit. Expected 90, found {quiz.get('time_limit')}")
    except:
        feedback.append("Invalid time limit value.")

    # 4. Allowed Attempts (10 pts)
    try:
        if int(float(quiz.get('allowed_attempts', 0))) == 1:
            score += 10
            feedback.append("Allowed attempts correct (1).")
        else:
            feedback.append(f"Incorrect attempts allowed. Expected 1, found {quiz.get('allowed_attempts')}")
    except:
        feedback.append("Invalid attempts value.")

    # 5. Access Code (15 pts)
    if quiz.get('access_code') == 'BIO101FINAL':
        score += 15
        feedback.append("Access code correct.")
    else:
        feedback.append(f"Incorrect access code. Expected 'BIO101FINAL', found '{quiz.get('access_code')}'")

    # 6. Boolean Settings (10 pts total)
    # Canvas exports booleans as 't'/'f' or 'true'/'false' usually
    shuffle = str(quiz.get('shuffle_answers', '')).lower()
    one_q = str(quiz.get('one_question_at_a_time', '')).lower()
    
    if shuffle in ['t', 'true', '1', 'yes']:
        score += 5
        feedback.append("Shuffle answers enabled.")
    else:
        feedback.append("Shuffle answers NOT enabled.")

    if one_q in ['t', 'true', '1', 'yes']:
        score += 5
        feedback.append("One question at a time enabled.")
    else:
        feedback.append("One question at a time NOT enabled.")

    # 7. Date Verification (15 pts total)
    # We compare the set dates to the task start time
    task_start = datetime.fromtimestamp(result.get('task_start', 0), tz=timezone.utc)
    
    def check_date(date_str, offset_days, name):
        pts = 0
        msg = ""
        actual_date = parse_canvas_date(date_str)
        if actual_date:
            target_date = task_start + timedelta(days=offset_days)
            # Allow +/- 48 hours tolerance for "X days from today" interpretation and timezone diffs
            diff = abs((actual_date - target_date).total_seconds())
            if diff <= 48 * 3600:
                pts = 5
                msg = f"{name} correct."
            else:
                msg = f"{name} incorrect. Set to {actual_date}, expected approx {target_date}."
        else:
            msg = f"{name} not set."
        return pts, msg

    d_pts, d_msg = check_date(quiz.get('due_at'), 21, "Due Date")
    score += d_pts
    feedback.append(d_msg)

    u_pts, u_msg = check_date(quiz.get('unlock_at'), 20, "Available From")
    score += u_pts
    feedback.append(u_msg)

    l_pts, l_msg = check_date(quiz.get('lock_at'), 22, "Available Until")
    score += l_pts
    feedback.append(l_msg)

    # 8. Description Content (5 pts)
    desc = str(quiz.get('description', '')).lower()
    if 'comprehensive final' in desc and 'closed-book' in desc:
        score += 5
        feedback.append("Description contains required phrases.")
    else:
        feedback.append("Description missing required phrases ('comprehensive final', 'closed-book').")

    # 9. Published State (10 pts)
    if quiz.get('workflow_state') == 'available':
        score += 10
        feedback.append("Quiz is published.")
    else:
        feedback.append(f"Quiz is NOT published (state: {quiz.get('workflow_state')}).")

    # 10. Anti-Gaming Check
    # Ensure the quiz ID didn't exist before (using count delta as proxy, or ID check if we had pre-IDs)
    if result.get('current_count', 0) <= result.get('initial_count', 0):
        # We found a quiz, but count didn't increase? 
        # Might be editing an existing one? Task says "Create a new Quiz".
        # We will penalize heavily if we suspect no new work was done.
        # However, purely checking ID creation time vs task start is better.
        created_at = parse_canvas_date(quiz.get('created_at'))
        if created_at and created_at < task_start:
             score = 0
             feedback = ["FAILED: Detected pre-existing quiz. You must CREATE a new quiz."]

    return {
        "passed": score >= 60 and quiz.get('title', '').strip().lower() == target_title.lower(),
        "score": score,
        "feedback": " | ".join(feedback)
    }