#!/usr/bin/env python3
"""
Verifier for create_ess_user_accounts task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_ess_user_accounts(traj, env_info, task_info):
    """
    Verify that two ESS user accounts were created correctly.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Retrieve result JSON
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

    # 3. Parse Data
    score = 0
    max_score = 100
    feedback_parts = []
    
    users = result.get('users', {})
    targets = result.get('targets', {})
    ess_role_id = str(result.get('ess_role_id', '2'))
    
    initial_count = int(result.get('initial_user_count', 0))
    final_count = int(result.get('final_user_count', 0))
    
    # 4. Verify User 1: lisa.andrews (45 points total)
    lisa = users.get('lisa.andrews', {})
    if lisa.get('exists'):
        score += 15
        feedback_parts.append("Lisa: Account created (+15)")
        
        # Check Role (ESS)
        if str(lisa.get('role_id')) == ess_role_id:
            score += 10
            feedback_parts.append("Lisa: Role ESS (+10)")
        else:
            feedback_parts.append(f"Lisa: Wrong role ID {lisa.get('role_id')}")

        # Check Status (Enabled=1)
        if str(lisa.get('status')) == '1':
            score += 5
            feedback_parts.append("Lisa: Enabled (+5)")
        else:
            feedback_parts.append("Lisa: Not enabled")
            
        # Check Employee Linkage
        if str(lisa.get('linked_emp_number')) == str(targets.get('lisa_emp_id')):
            score += 15
            feedback_parts.append("Lisa: Linked correctly (+15)")
        else:
            feedback_parts.append("Lisa: Linked to wrong employee")
    else:
        feedback_parts.append("Lisa: Account NOT found")

    # 5. Verify User 2: david.morris (45 points total)
    david = users.get('david.morris', {})
    if david.get('exists'):
        score += 15
        feedback_parts.append("David: Account created (+15)")
        
        # Check Role (ESS)
        if str(david.get('role_id')) == ess_role_id:
            score += 10
            feedback_parts.append("David: Role ESS (+10)")
        else:
            feedback_parts.append(f"David: Wrong role ID {david.get('role_id')}")

        # Check Status (Enabled=1)
        if str(david.get('status')) == '1':
            score += 5
            feedback_parts.append("David: Enabled (+5)")
        else:
            feedback_parts.append("David: Not enabled")
            
        # Check Employee Linkage
        if str(david.get('linked_emp_number')) == str(targets.get('david_emp_id')):
            score += 15
            feedback_parts.append("David: Linked correctly (+15)")
        else:
            feedback_parts.append("David: Linked to wrong employee")
    else:
        feedback_parts.append("David: Account NOT found")

    # 6. Anti-Gaming Check (10 points)
    # Ensure exactly 2 users were added to the system
    count_diff = final_count - initial_count
    if count_diff == 2:
        score += 10
        feedback_parts.append("Exact count match (+10)")
    elif count_diff > 2:
        feedback_parts.append(f"Too many users created (+{count_diff})")
    elif count_diff < 2:
        feedback_parts.append(f"Not enough users created (+{count_diff})")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }