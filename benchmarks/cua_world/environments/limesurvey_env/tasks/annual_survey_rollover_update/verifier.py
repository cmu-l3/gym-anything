#!/usr/bin/env python3
"""
Verifier for annual_survey_rollover_update task.

Criteria:
1. New survey 'Employee Pulse 2025' exists (20 pts)
2. Original survey 'Employee Pulse 2024' is intact (10 pts)
3. '2024 Initiatives' group removed from new survey (20 pts)
4. '2025 Strategic Focus' group added to new survey (10 pts)
5. 'AI_USAGE' question added (List Radio 'L') (15 pts)
6. 'INNOVATION_IDEA' question added (Long Text 'T') (15 pts)
7. New survey is Active (10 pts)

Pass threshold: 80/100
"""

import json
import os
import tempfile

def verify_annual_survey_rollover_update(traj, env_info, task_info):
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
    feedback = []

    # 1. Target Survey Found (20 pts)
    if result.get('target_found', False):
        score += 20
        feedback.append("New survey 'Employee Pulse 2025' created.")
    else:
        feedback.append("Failed: 'Employee Pulse 2025' survey not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # 2. Source Survey Integrity (10 pts)
    if result.get('source_exists', False) and result.get('source_intact', False):
        score += 10
        feedback.append("Original survey preserved correctly.")
    else:
        feedback.append("Warning: Original survey was deleted or modified.")

    # 3. Obsolete Group Removal (20 pts)
    if result.get('obsolete_group_gone', False):
        score += 20
        feedback.append("Obsolete group '2024 Initiatives' removed.")
    else:
        feedback.append("Failed: '2024 Initiatives' group still present in new survey.")

    # 4. New Group Creation (10 pts)
    if result.get('new_group_found', False):
        score += 10
        feedback.append("New group '2025 Strategic Focus' created.")
    else:
        feedback.append("Failed: '2025 Strategic Focus' group not found.")

    # 5. Q1 Check (15 pts)
    if result.get('q1_found', False):
        q1_type = result.get('q1_type', '')
        if q1_type == 'L':
            score += 15
            feedback.append("Question 'AI_USAGE' added correctly.")
        else:
            score += 5
            feedback.append(f"Question 'AI_USAGE' exists but wrong type (expected 'L', got '{q1_type}').")
    else:
        feedback.append("Failed: Question 'AI_USAGE' not found.")

    # 6. Q2 Check (15 pts)
    if result.get('q2_found', False):
        q2_type = result.get('q2_type', '')
        # T = Long free text, U = Huge free text. Accept either for 'Long Text' intent
        if q2_type in ['T', 'U']:
            score += 15
            feedback.append("Question 'INNOVATION_IDEA' added correctly.")
        else:
            score += 5
            feedback.append(f"Question 'INNOVATION_IDEA' exists but wrong type (expected 'T', got '{q2_type}').")
    else:
        feedback.append("Failed: Question 'INNOVATION_IDEA' not found.")

    # 7. Activation (10 pts)
    if result.get('target_active', 'N') == 'Y':
        score += 10
        feedback.append("New survey is Active.")
    else:
        feedback.append("Failed: New survey is not active.")

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }