#!/usr/bin/env python3
"""
Verifier for create_crm_salesperson task.

Criteria:
1. User "Sarah Johnson" exists (20 pts)
2. Login/Email is correct (15 pts)
3. CRM Access is "User: Own Documents Only" (30 pts)
   - Must have sales_team.group_sale_salesman
4. CRM Access is NOT "Administrator" (10 pts)
   - Must NOT have sales_team.group_sale_manager
5. Added to "Direct Sales" team (20 pts)
6. Anti-gaming: Created during task (5 pts)

Pass Threshold: 65/100
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_crm_salesperson(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. User Existence
    if result.get('user_found'):
        score += 20
        feedback.append("User 'Sarah Johnson' found.")
    else:
        return {"passed": False, "score": 0, "feedback": "User 'Sarah Johnson' was not created."}

    # 2. Login Check
    user_data = result.get('user_data', {})
    expected_login = "sarah.johnson@yourcompany.example.com"
    if user_data.get('login') == expected_login:
        score += 15
        feedback.append("Email/Login is correct.")
    else:
        feedback.append(f"Incorrect email. Expected {expected_login}, got {user_data.get('login')}.")

    # 3 & 4. Access Rights
    groups = result.get('groups', [])
    has_salesman = 'sales_team.group_sale_salesman' in groups
    has_manager = 'sales_team.group_sale_manager' in groups

    if has_salesman:
        score += 30
        feedback.append("Correct CRM Salesperson access granted.")
        
        # Check negative constraint (not admin)
        if not has_manager:
            score += 10
            feedback.append("Correctly restricted from Manager/Admin access.")
        else:
            feedback.append("Incorrect access: User was granted Manager rights (too permissive).")
    else:
        # Check if they gave manager rights but not salesman (sometimes implies salesman)
        if has_manager:
            score += 10 # Partial credit for giving some access
            feedback.append("Incorrect access: User granted Manager rights instead of basic Salesperson.")
        else:
            feedback.append("No CRM Sales permissions assigned.")

    # 5. Team Membership
    if result.get('team_member'):
        score += 20
        feedback.append(f"User correctly added to '{result.get('team_name')}' team.")
    else:
        feedback.append("User was NOT added to the 'Direct Sales' team.")

    # 6. Anti-gaming
    if result.get('timestamp_valid', False):
        score += 5
    elif result.get('current_user_count', 0) > result.get('initial_user_count', 0):
        # Fallback if timestamp fails but count increased
        score += 5
        feedback.append("New user count confirmed.")
    else:
        feedback.append("Warning: User creation timestamp check failed (possible pre-existing user).")

    return {
        "passed": score >= 65,
        "score": score,
        "feedback": " ".join(feedback)
    }