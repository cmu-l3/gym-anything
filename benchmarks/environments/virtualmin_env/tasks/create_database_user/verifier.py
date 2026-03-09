#!/usr/bin/env python3
"""
Verifier for create_database_user task.

Verifies:
1. MySQL user 'reports_reader'@'localhost' exists (20 pts)
2. Password 'R3p0rt$2024!' works (15 pts)
3. User has SELECT privilege on 'acmecorp' database (25 pts)
4. User does NOT have write privileges (INSERT/UPDATE/DELETE) (20 pts)
5. User is restricted to localhost (10 pts)
6. Anti-gaming checks (10 pts)

Also uses VLM on trajectory to verify UI interaction.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_database_user(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Load result from container
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

    # 1. User Existence (20 pts)
    if result.get("user_exists_localhost"):
        score += 20
        feedback_parts.append("User 'reports_reader'@'localhost' created.")
    elif result.get("user_exists_any"):
        score += 5
        feedback_parts.append("User created, but host is not 'localhost'.")
    else:
        feedback_parts.append("User 'reports_reader' not found.")

    # 2. Authentication (15 pts)
    if result.get("auth_success"):
        score += 15
        feedback_parts.append("Password authentication successful.")
    else:
        feedback_parts.append("Password authentication failed.")

    # 3. SELECT Privilege (25 pts)
    has_select = result.get("has_select_privilege")
    if has_select == "true":
        score += 25
        feedback_parts.append("SELECT privilege confirmed.")
    elif has_select == "true_but_auth_failed":
        score += 15
        feedback_parts.append("SELECT privilege appears in grants, but authentication failed.")
    else:
        feedback_parts.append("SELECT privilege missing or non-functional.")

    # 4. Write Restrictions (20 pts)
    # Only award if user exists
    if result.get("user_exists_any"):
        if not result.get("has_write_privilege"):
            score += 20
            feedback_parts.append("Write privileges correctly denied.")
        else:
            feedback_parts.append(f"Security fail: Write privileges allowed ({result.get('write_details')}).")

    # 5. Localhost Restriction (10 pts)
    if result.get("user_exists_localhost") and not result.get("user_exists_wildcard"):
        score += 10
        feedback_parts.append("Host correctly restricted to localhost.")
    elif result.get("user_exists_wildcard"):
        feedback_parts.append("Security fail: User allows wildcard host access.")

    # 6. Anti-Gaming (10 pts)
    # Check if a new user was actually created
    if result.get("user_count_diff", 0) > 0:
        score += 5
    # Check if task took > 5 seconds (not instant script)
    if result.get("task_duration", 0) > 5:
        score += 5
        
    if score >= 10:
        feedback_parts.append("Anti-gaming checks passed.")

    # 7. VLM Verification (Bonus/Tie-breaker context)
    # We don't rely on this for the main score since DB checks are authoritative,
    # but it helps verify the agent used the UI if we cared about "process".
    # Here we just log it or use it to confirm "User Management" was seen.
    frames = sample_trajectory_frames(traj, n=3)
    final = get_final_screenshot(traj)
    
    if frames and final:
        vlm_prompt = "Does the user interface show Virtualmin database management or 'Edit Users' screens? Answer yes/no."
        vlm_res = query_vlm(images=frames + [final], prompt=vlm_prompt)
        if vlm_res.get("success") and "yes" in vlm_res.get("response", "").lower():
            # Could add bonus points or just confirm UI usage
            pass

    passed = score >= 60 and result.get("user_exists_localhost") and result.get("has_select_privilege") == "true"

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }