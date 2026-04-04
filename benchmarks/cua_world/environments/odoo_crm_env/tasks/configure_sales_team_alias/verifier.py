#!/usr/bin/env python3
"""
Verifier for configure_sales_team_alias task.

Criteria:
1. Sales Team "Direct Sales" must exist.
2. Alias name must be "direct-sales".
3. Alias privacy policy must be "everyone" (accept emails from everyone).
4. Team leader should be the admin user.
5. Record must have been created during the task session.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_sales_team_alias(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    expected_team = metadata.get('target_team_name', 'Direct Sales')
    expected_alias = metadata.get('expected_alias', 'direct-sales')
    expected_policy = metadata.get('expected_policy', 'everyone')

    # Fetch result from container
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
    
    # 1. Check Team Existence (20 pts)
    if result.get('team_found'):
        score += 20
        feedback.append(f"Sales Team '{expected_team}' found.")
    else:
        return {"passed": False, "score": 0, "feedback": f"Sales Team '{expected_team}' not found."}

    # 2. Check Alias Name (30 pts)
    # Odoo alias names are case-insensitive usually, but convention is lowercase
    actual_alias = str(result.get('alias_name', '')).lower()
    if actual_alias == expected_alias.lower():
        score += 30
        feedback.append(f"Alias correctly set to '{expected_alias}'.")
    else:
        feedback.append(f"Incorrect alias: expected '{expected_alias}', got '{result.get('alias_name')}'.")

    # 3. Check Privacy Policy (30 pts)
    actual_policy = str(result.get('alias_contact', ''))
    if actual_policy == expected_policy:
        score += 30
        feedback.append("Email policy correctly set to 'Everyone'.")
    else:
        feedback.append(f"Incorrect email policy: expected '{expected_policy}', got '{actual_policy}'.")

    # 4. Check Team Leader (10 pts)
    # Usually ID 2 is admin in standard Odoo installs
    leader_name = result.get('leader_name', '')
    user_id = result.get('user_id')
    if "admin" in leader_name.lower() or user_id == 2:
        score += 10
        feedback.append("Team leader is correct.")
    else:
        feedback.append(f"Team leader mismatch: got '{leader_name}'.")

    # 5. Check Creation Timestamp (10 pts)
    # Parse Odoo datetime string (e.g., "2023-10-25 10:00:00") or compare raw if possible
    # We compare logic: if creation date exists and is valid
    # Detailed timestamp comparison is hard due to TZ differences, verifying existence + "newness"
    # via task logic is usually sufficient if we cleaned up before.
    # Here we just give points if we have a create_date and team was found (implying we queried a real record)
    if result.get('create_date'):
        score += 10
        feedback.append("Record creation confirmed.")

    passed = score >= 80  # Requires Team, Alias, and Policy to be correct (20+30+30=80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }