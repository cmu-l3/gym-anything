#!/usr/bin/env python3
"""
Verifier for consolidate_employee_tags task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_consolidate_employee_tags(traj, env_info, task_info):
    """
    Verifies that:
    1. 'Contractor' tag exists.
    2. Target employees (previously 'Consultant') now have 'Contractor'.
    3. Target employees NO LONGER have 'Consultant'.
    4. No employees in the system have 'Consultant'.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring Criteria
    score = 0
    feedback = []

    # 1. Tag Creation (10 pts)
    if result.get('contractor_tag_exists'):
        score += 10
        feedback.append("'Contractor' tag exists.")
    else:
        feedback.append("'Contractor' tag NOT found.")

    # 2. System Cleanliness (10 pts)
    # Count of employees with 'Consultant'
    consultant_count = result.get('consultant_tag_count', -1)
    if consultant_count == 0:
        score += 10
        feedback.append("No employees tagged 'Consultant'.")
    elif consultant_count > 0:
        feedback.append(f"{consultant_count} employee(s) still tagged 'Consultant'.")
    else:
        feedback.append("Could not determine 'Consultant' tag usage.")

    # 3. Target Updates (80 pts)
    targets = result.get('targets_processed', [])
    total_targets = len(targets)
    
    if total_targets == 0:
        feedback.append("No target employees were tracked (setup error?).")
    else:
        correct_targets = 0
        for t in targets:
            emp_name = t.get('name', 'Unknown')
            if t.get('is_correct'):
                correct_targets += 1
            else:
                issues = []
                if not t.get('has_contractor'): issues.append("missing 'Contractor'")
                if t.get('has_consultant'): issues.append("still has 'Consultant'")
                feedback.append(f"Employee {emp_name}: {', '.join(issues)}.")
        
        # Calculate score for targets
        # 80 points distributed among targets
        target_score = (correct_targets / total_targets) * 80
        score += target_score
        feedback.append(f"{correct_targets}/{total_targets} target employees updated correctly.")

    passed = (score >= 99) # Strict pass for data hygiene tasks

    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback)
    }