#!/usr/bin/env python3
"""
Verifier for SERVQUAL Dual Scale Survey Task.

Scoring Criteria:
1. Survey exists with correct title (Gate)
2. At least 2 question groups (15 pts)
3. Array Dual Scale question exists (25 pts)
4. Dual Scale question has >= 5 sub-questions (15 pts)
5. Dual Scale question has 2 distinct answer scales configured (15 pts)
6. Long Free Text question exists (5 pts)
7. Survey is Active (15 pts)
8. Survey is Anonymized (10 pts)

Pass Threshold: 70/100
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_servqual_survey(traj, env_info, task_info):
    # 1. Setup: Retrieve result from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env not available"}
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/servqual_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    survey_found = result.get("survey_found", False)
    title = result.get("title", "")
    active = result.get("active", "N")
    anonymized = result.get("anonymized", "N")
    group_count = result.get("group_count", 0)
    dual_scale_found = result.get("dual_scale_found", False)
    subquestion_count = result.get("subquestion_count", 0)
    scale_count = result.get("scale_count", 0)
    free_text_found = result.get("free_text_found", "false")

    score = 0
    feedback = []

    # 3. Verify Criteria
    
    # Gate: Survey must exist
    if not survey_found:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No survey found with 'SERVQUAL' or 'Service Quality' in the title."
        }
    
    feedback.append(f"Survey found: '{title}'")

    # Criterion: Question Groups (15 pts)
    if group_count >= 2:
        score += 15
        feedback.append("Correctly created multiple question groups (15/15).")
    elif group_count == 1:
        score += 5
        feedback.append("Only 1 question group found, expected at least 2 (5/15).")
    else:
        feedback.append("No question groups found (0/15).")

    # Criterion: Dual Scale Question (25 pts)
    if dual_scale_found:
        score += 25
        feedback.append("Array (Dual Scale) question type found (25/25).")
        
        # Criterion: Sub-questions (15 pts)
        # SERVQUAL has 5 dimensions. We accept >= 4 as close enough.
        if subquestion_count >= 5:
            score += 15
            feedback.append(f"Correct number of sub-questions ({subquestion_count}) found (15/15).")
        elif subquestion_count >= 1:
            score += 5
            feedback.append(f"Found {subquestion_count} sub-questions, expected 5 (5/15).")
        else:
            feedback.append("No sub-questions added to the array (0/15).")

        # Criterion: Dual Scales Configured (15 pts)
        # Must have answer options for both scales
        if scale_count >= 2:
            score += 15
            feedback.append("Both answer scales configured correctly (15/15).")
        elif scale_count == 1:
            score += 5
            feedback.append("Only one answer scale configured (5/15).")
        else:
            feedback.append("No answer options configured for the scales (0/15).")

    else:
        feedback.append("Array (Dual Scale) question NOT found. This is the core requirement (0/55).")

    # Criterion: Free Text Question (5 pts)
    if free_text_found == "true":
        score += 5
        feedback.append("Long Free Text question found (5/5).")
    elif free_text_found == "true_alt_type":
        score += 3
        feedback.append("Free text question found but incorrect type (Short/Huge instead of Long) (3/5).")
    else:
        feedback.append("Feedback text question not found (0/5).")

    # Criterion: Active (15 pts)
    if active == "Y":
        score += 15
        feedback.append("Survey is active (15/15).")
    else:
        feedback.append("Survey is NOT active (0/15).")

    # Criterion: Anonymized (10 pts)
    if anonymized == "Y":
        score += 10
        feedback.append("Survey is anonymized (10/10).")
    else:
        feedback.append("Survey is NOT anonymized (0/10).")

    # 4. Final Result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }