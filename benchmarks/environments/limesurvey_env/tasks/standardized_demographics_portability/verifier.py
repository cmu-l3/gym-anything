#!/usr/bin/env python3
"""
Verifier for standardized_demographics_portability task.

Criteria:
1. Master Template Survey created and contains correct questions (40 pts)
2. Export File (.lsg) created and valid (20 pts)
3. Target Survey created and contains imported questions (40 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_standardized_demographics_portability(traj, env_info, task_info):
    """
    Verify that the agent created a master survey, exported the group,
    and imported it into a new survey.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    # 1. Check Master Template (Source) - 40 pts
    source = result.get('source_survey', {})
    if source.get('sid'):
        score += 10
        feedback.append("Master survey created (+10).")
        
        # Check Group
        if source.get('has_group', 0) > 0:
            score += 5
            feedback.append("Master group created (+5).")
        
        # Check Questions (5 pts each)
        if source.get('q_age', 0) > 0: score += 5
        if source.get('q_emp', 0) > 0: score += 5
        if source.get('q_edu', 0) > 0: score += 5
        
        # Check Options (10 pts)
        if source.get('edu_options', 0) >= 5:
            score += 10
            feedback.append("Education options configured (+10).")
        else:
            feedback.append(f"Missing education options in master (Found {source.get('edu_options')}).")
    else:
        feedback.append("Master survey NOT found.")

    # 2. Check Export File - 20 pts
    file_check = result.get('file_check', {})
    if file_check.get('exists') and file_check.get('created_during_task'):
        # Check size to ensure it's not empty
        if file_check.get('size', 0) > 100:
            score += 20
            feedback.append("Group exported to .lsg file (+20).")
        else:
            score += 5
            feedback.append("Export file exists but is suspicious (too small) (+5).")
    else:
        feedback.append("Export file (.lsg) not found or not created during task.")

    # 3. Check Target Survey (Import) - 40 pts
    target = result.get('target_survey', {})
    if target.get('sid'):
        score += 10
        feedback.append("Target survey created (+10).")
        
        # Check if IDs are different (anti-gaming: didn't just rename the source)
        if target.get('sid') == source.get('sid'):
            score -= 10
            feedback.append("WARNING: Target SID matches Source SID. You renamed the survey instead of creating a new one (-10).")
        
        # Check Content (inherited from import)
        imported_content_score = 0
        if target.get('has_group', 0) > 0: imported_content_score += 10
        if target.get('q_age', 0) > 0: imported_content_score += 5
        if target.get('q_edu', 0) > 0: imported_content_score += 5
        if target.get('q_emp', 0) > 0: imported_content_score += 5
        if target.get('edu_options', 0) >= 5: imported_content_score += 5
        
        score += imported_content_score
        if imported_content_score >= 30:
            feedback.append("Demographics group successfully imported into target survey (+30).")
        else:
            feedback.append("Import incomplete or missing questions in target survey.")
            
    else:
        feedback.append("Target survey ('Social Interaction Study 2024') NOT found.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }