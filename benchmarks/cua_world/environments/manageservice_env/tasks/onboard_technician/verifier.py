#!/usr/bin/env python3
"""
Verifier for onboard_technician task.
Checks if the Skill and Technician were created and correctly linked in the database.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_onboard_technician(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring Criteria
    score = 0
    feedback_parts = []
    
    # 1. Skill Created (20 pts)
    if result.get("skill_found"):
        score += 20
        feedback_parts.append("Skill 'AWS Certified Solutions Architect' created.")
    else:
        feedback_parts.append("Skill NOT found.")

    # 2. Technician Created (20 pts)
    if result.get("technician_found"):
        score += 20
        feedback_parts.append("Technician 'Elena Rodriguez' created.")
    else:
        feedback_parts.append("Technician NOT found.")

    # 3. Login Configured (20 pts)
    if result.get("login_found"):
        score += 20
        feedback_parts.append(f"Login '{result.get('login_name')}' configured.")
    else:
        feedback_parts.append("Login NOT configured correctly.")

    # 4. Cost Per Hour (20 pts)
    # Allow string comparison or float with tolerance
    try:
        cost_val = float(result.get("cost_value", 0))
        if 84.9 <= cost_val <= 85.1:
            score += 20
            feedback_parts.append(f"Hourly cost ${cost_val} is correct.")
        else:
            feedback_parts.append(f"Hourly cost ${cost_val} is incorrect (expected $85).")
    except ValueError:
        feedback_parts.append("Hourly cost not a valid number.")

    # 5. Skill Assigned (20 pts)
    # Verify the link between user and skill
    if result.get("skill_link_found"):
        score += 20
        feedback_parts.append("Skill successfully assigned to technician.")
    else:
        feedback_parts.append("Skill was created but NOT assigned to the technician.")

    # Bonus/Sanity check: Role
    if result.get("role_assigned"):
        feedback_parts.append("Correct admin role assigned.")
    else:
        feedback_parts.append("Warning: Admin role not assigned (might affect login).")

    # Pass Threshold: 80 points
    # Must at least have Tech, Skill, and Login working
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }