#!/usr/bin/env python3
"""
Verifier for Cascading Brand Exclusion Logic Task.

Verifies:
1. Survey exists and is active.
2. Q1 (Usage) exists as Multiple Choice.
3. Q2 (Rejection) exists as Multiple Choice and excludes Q1 ('array_filter_exclude').
4. Q3 (Reasons) exists as Array and includes Q2 ('array_filter' / 'filter').
5. Subquestion codes match exactly across Q1, Q2, and Q3 (critical for logic to work).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cascading_logic(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
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
    
    # 1. Check Survey Structure (10 pts)
    if not result.get('survey_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Survey 'Smartphone Brand Funnel 2026' not found."
        }
    
    score += 5
    if result.get('is_active'):
        score += 5
        feedback_parts.append("Survey is active.")
    else:
        feedback_parts.append("Survey found but NOT active.")

    # Get questions
    q1 = result.get('q1') or {}
    q2 = result.get('q2') or {}
    q3 = result.get('q3') or {}

    # 2. Check Q1 - Usage (15 pts)
    # Type M = Multiple Choice
    if q1 and q1.get('type') == 'M':
        score += 15
        feedback_parts.append("Q1_USE created correctly.")
    elif q1:
        score += 5
        feedback_parts.append(f"Q1_USE exists but wrong type ({q1.get('type')}).")
    else:
        feedback_parts.append("Q1_USE not found.")

    # 3. Check Q2 - Rejection (25 pts)
    # Type M = Multiple Choice, Attribute array_filter_exclude = Q1_USE
    q2_pass = False
    if q2:
        if q2.get('type') == 'M':
            score += 10
            # Check exclusion logic
            exclude = q2.get('exclude_attr', '')
            if exclude and 'Q1_USE' in exclude:
                score += 15
                q2_pass = True
                feedback_parts.append("Q2_REJECT logic correct (Exclusion filter).")
            else:
                feedback_parts.append(f"Q2_REJECT missing/wrong exclusion attribute (found: '{exclude}').")
        else:
            feedback_parts.append(f"Q2_REJECT wrong type ({q2.get('type')}).")
    else:
        feedback_parts.append("Q2_REJECT not found.")

    # 4. Check Q3 - Reasons (25 pts)
    # Type F = Array, Attribute filter = Q2_REJECT
    # Note: In DB, 'array_filter' attribute is often stored as 'filter' in lime_question_attributes
    q3_pass = False
    if q3:
        # F is Array (flexible labels)
        if q3.get('type') == 'F':
            score += 10
            # Check inclusion logic
            include = q3.get('filter_attr', '')
            if include and 'Q2_REJECT' in include:
                score += 15
                q3_pass = True
                feedback_parts.append("Q3_WHY logic correct (Inclusion filter).")
            else:
                feedback_parts.append(f"Q3_WHY missing/wrong filter attribute (found: '{include}').")
        else:
            feedback_parts.append(f"Q3_WHY wrong type ({q3.get('type')}).")
    else:
        feedback_parts.append("Q3_WHY not found.")

    # 5. Check Subquestion Consistency (25 pts)
    # Codes must match for filters to work
    if q1 and q2 and q3:
        s1 = set(q1.get('sub_codes', '').split(','))
        s2 = set(q2.get('sub_codes', '').split(','))
        s3 = set(q3.get('sub_codes', '').split(','))

        # Filter out empty strings
        s1 = {x for x in s1 if x}
        s2 = {x for x in s2 if x}
        s3 = {x for x in s3 if x}

        # We expect at least 5 brands
        if len(s1) >= 5:
            # Check if Q2 has the same codes as Q1
            q1_q2_match = (s1 == s2)
            # Check if Q3 has the same codes as Q2 (or Q1)
            q2_q3_match = (s2 == s3)

            if q1_q2_match and q2_q3_match:
                score += 25
                feedback_parts.append("Subquestion codes match perfectly across cascading logic.")
            else:
                score += 5
                feedback_parts.append(f"Subquestion codes mismatch. Q1:{len(s1)}, Q2:{len(s2)}, Q3:{len(s3)} items.")
        else:
            feedback_parts.append("Insufficient subquestions found.")
    else:
        feedback_parts.append("Cannot verify code consistency (missing questions).")

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }