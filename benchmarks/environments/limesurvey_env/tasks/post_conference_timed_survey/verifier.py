#!/usr/bin/env python3
"""
Verifier for post_conference_timed_survey task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_post_conference_survey(traj, env_info, task_info):
    """
    Verifies the survey configuration for the Post-Conference task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_start = metadata.get('expected_start_date', '2025-03-15')
    expected_expiry = metadata.get('expected_expiry_date', '2025-03-29')
    expected_url_part = metadata.get('expected_end_url', 'datasciencesummit2024.org/thank-you')
    
    # Load result from container
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
    
    # 1. Gate: Survey Exists (Pass/Fail)
    if not result.get('found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No survey found with 'Data Science Summit' in the title."
        }
    
    score += 5 # Base points for finding the survey
    feedback.append(f"Survey found: {result.get('title')}")

    # 2. Schedule Checks (30 pts)
    # Start Date
    actual_start = result.get('start_date', '')
    if expected_start in str(actual_start):
        score += 15
        feedback.append("Start date correct.")
    else:
        feedback.append(f"Start date incorrect. Expected {expected_start}, got {actual_start}")

    # Expiry Date
    actual_expiry = result.get('expires_date', '')
    if expected_expiry in str(actual_expiry):
        score += 15
        feedback.append("Expiry date correct.")
    else:
        feedback.append(f"Expiry date incorrect. Expected {expected_expiry}, got {actual_expiry}")

    # 3. Presentation Settings (20 pts)
    # Show Progress (Y)
    show_prog = result.get('show_progress', 'N')
    if show_prog == 'Y':
        score += 10
        feedback.append("Progress bar enabled.")
    else:
        feedback.append(f"Progress bar not enabled (value: {show_prog}).")

    # Allow Prev (N)
    allow_prev = result.get('allow_prev', 'Y')
    if allow_prev == 'N':
        score += 10
        feedback.append("Backward navigation disabled.")
    else:
        feedback.append(f"Backward navigation not disabled (value: {allow_prev}).")

    # 4. Text & URLs (25 pts)
    # End URL
    actual_url = result.get('end_url', '')
    if expected_url_part in actual_url:
        score += 10
        feedback.append("End URL correct.")
    else:
        feedback.append(f"End URL incorrect. Expected to contain '{expected_url_part}', got '{actual_url}'")

    # Welcome Text (Must mention conference)
    welcome_text = result.get('welcome_text', '').lower()
    if 'data science summit' in welcome_text:
        score += 10
        feedback.append("Welcome text references conference.")
    else:
        feedback.append("Welcome text missing conference reference.")
        
    # Question Groups exists
    if result.get('group_count', 0) >= 1:
        score += 5
        feedback.append("Question group created.")
    else:
        feedback.append("No question groups found.")

    # 5. Ranking Question (20 pts)
    if result.get('ranking_question_exists'):
        score += 10
        feedback.append("Ranking question type found.")
        
        opt_count = result.get('answer_option_count', 0)
        if opt_count >= 5:
            score += 10
            feedback.append(f"Correct number of answer options ({opt_count}).")
        else:
            feedback.append(f"Insufficient answer options: {opt_count} (expected 5).")
    else:
        feedback.append("No Ranking question (Type 'R') found.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }