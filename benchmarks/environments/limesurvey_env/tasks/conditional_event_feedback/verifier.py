#!/usr/bin/env python3
"""
Verifier for conditional_event_feedback task.

Criteria:
1. Survey 'TechSummit' exists (Gate)
2. 5 Question Groups (15 pts)
3. >= 10 Questions (15 pts)
4. >= 2 Groups have conditional logic (25 pts)
5. >= 2 Questions have conditional logic (25 pts)
6. Attendance question is List Radio with >= 3 options (10 pts)
7. Survey is Active (10 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_conditional_event_feedback(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result file
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
    
    # 1. Gate Check: Survey Found
    if not result.get('survey_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Survey with title containing 'TechSummit' not found."
        }
    
    # 2. Group Count (15 pts)
    # Exact match of 5 groups preferred
    groups = result.get('group_count', 0)
    if groups == 5:
        score += 15
        feedback.append("Correct number of question groups (5).")
    elif groups >= 4:
        score += 10
        feedback.append(f"Group count close (found {groups}, expected 5).")
    else:
        feedback.append(f"Incorrect group count: {groups} (expected 5).")

    # 3. Question Count (15 pts)
    # Expected at least 10 parent questions
    questions = result.get('question_count', 0)
    if questions >= 10:
        score += 15
        feedback.append(f"Sufficient question count ({questions}).")
    elif questions >= 5:
        score += 7
        feedback.append(f"Low question count ({questions}, expected >= 10).")
    else:
        feedback.append(f"Too few questions: {questions}.")

    # 4. Group Branching Logic (25 pts)
    # We need at least 2 groups (Venue, Virtual) to have relevance equations
    groups_rel = result.get('groups_with_relevance', 0)
    if groups_rel >= 2:
        score += 25
        feedback.append("Group-level conditional branching configured correctly.")
    elif groups_rel == 1:
        score += 10
        feedback.append("Only 1 group has conditional logic (expected 2).")
    else:
        feedback.append("Missing group-level branching logic (Venue/Virtual groups need conditions).")

    # 5. Question Branching Logic (25 pts)
    # We need at least 2 questions (Testimonial, Issues) to have relevance equations
    qs_rel = result.get('questions_with_relevance', 0)
    if qs_rel >= 2:
        score += 25
        feedback.append("Question-level conditional branching configured correctly.")
    elif qs_rel == 1:
        score += 10
        feedback.append("Only 1 question has conditional logic (expected 2).")
    else:
        feedback.append("Missing question-level branching logic (Testimonial/Issues need conditions).")

    # 6. Attendance Question Structure (10 pts)
    q_type = result.get('attendance_q_type', '')
    q_opts = result.get('attendance_options', 0)
    if q_type == 'L' and q_opts >= 3:
        score += 10
        feedback.append("Attendance question correctly configured (List Radio, 3+ options).")
    elif q_type == 'L':
        score += 5
        feedback.append("Attendance question exists but has fewer than 3 options.")
    else:
        feedback.append("Attendance question not found or wrong type (expected List Radio).")

    # 7. Active Status (10 pts)
    active = str(result.get('active', 'N'))
    if active == 'Y':
        score += 10
        feedback.append("Survey is active.")
    else:
        feedback.append("Survey is NOT active.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }