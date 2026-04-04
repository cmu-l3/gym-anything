#!/usr/bin/env python3
"""
Verifier for Cognitive Timed Assessment Task
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cognitive_timed_assessment(traj, env_info, task_info):
    """
    Verifies that the cognitive assessment survey was created with specific timing and navigation settings.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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
    feedback_parts = []
    
    # 1. Survey Existence (Gate)
    if not result.get('survey_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Survey titled 'Executive Function Screening 2025' not found."
        }

    # 2. Survey Navigation Settings (20 pts)
    # allow_prev should be 'N' (No backward navigation)
    # show_progress should be 'Y' (Show progress bar)
    allow_prev = result.get('allow_prev', 'Y')
    show_progress = result.get('show_progress', 'N')
    
    if allow_prev == 'N':
        score += 15
        feedback_parts.append("Backward navigation disabled (15/15)")
    else:
        feedback_parts.append("Backward navigation NOT disabled (0/15)")

    if show_progress == 'Y':
        score += 5
        feedback_parts.append("Progress bar enabled (5/5)")
    else:
        feedback_parts.append("Progress bar NOT enabled (0/5)")

    # 3. Question 1 (EF01) Verification (40 pts total)
    q1 = result.get('q1', {})
    if q1.get('found'):
        score += 5 # Base points for creating the question
        attrs = q1.get('attributes', {})
        
        # Time limit: 10
        if attrs.get('time_limit') == '10':
            score += 15
            feedback_parts.append("EF01 Timer set to 10s (15/15)")
        else:
            feedback_parts.append(f"EF01 Timer incorrect: {attrs.get('time_limit', 'None')} (0/15)")

        # Action: moveon
        if attrs.get('time_limit_action') == 'moveon':
            score += 10
            feedback_parts.append("EF01 Action set to 'Move on' (10/10)")
        else:
            feedback_parts.append(f"EF01 Action incorrect: {attrs.get('time_limit_action', 'None')} (0/10)")

        # Randomization: 1
        if attrs.get('random_order') == '1':
            score += 10
            feedback_parts.append("EF01 Randomization enabled (10/10)")
        else:
            feedback_parts.append("EF01 Randomization NOT enabled (0/10)")
    else:
        feedback_parts.append("Question EF01 not found (0/40)")

    # 4. Question 2 (EF02) Verification (35 pts total)
    q2 = result.get('q2', {})
    if q2.get('found'):
        score += 5 # Base points
        attrs = q2.get('attributes', {})
        
        # Time limit: 5
        if attrs.get('time_limit') == '5':
            score += 10
            feedback_parts.append("EF02 Timer set to 5s (10/10)")
        else:
            feedback_parts.append(f"EF02 Timer incorrect: {attrs.get('time_limit', 'None')} (0/10)")

        # Action: moveon
        if attrs.get('time_limit_action') == 'moveon':
            score += 10
            feedback_parts.append("EF02 Action set to 'Move on' (10/10)")
        else:
            feedback_parts.append(f"EF02 Action incorrect: {attrs.get('time_limit_action', 'None')} (0/10)")

        # Randomization: 1
        if attrs.get('random_order') == '1':
            score += 10
            feedback_parts.append("EF02 Randomization enabled (10/10)")
        else:
            feedback_parts.append("EF02 Randomization NOT enabled (0/10)")
    else:
        feedback_parts.append("Question EF02 not found (0/35)")

    # Pass Threshold: 80 points
    # Requires correct navigation + correct timers + randomization
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }