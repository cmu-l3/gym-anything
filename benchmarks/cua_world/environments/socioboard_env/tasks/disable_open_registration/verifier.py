#!/usr/bin/env python3
"""
Verifier for disable_open_registration task.

Verification Strategy (Multi-Signal):
1. HTTP Response Verification: Ensures the exact security banner text is present.
2. HTTP Status Verification: Ensures the login page wasn't broken by syntax errors (must be 200).
3. Route Security Verification: Checks if the /register route was disabled (status code changes from 200).
4. Code Modification Verification: Analyzes git diffs to ensure `routes/web.php` and `resources/views/` were actually modified.
5. VLM Trajectory Verification: Confirms visually that the agent edited code.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_disable_registration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_banner = metadata.get('expected_banner', "RESTRICTED SYSTEM: Authorized agency staff only.")

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    login_body = result.get('login_body', '')
    login_status = result.get('login_status', '000')
    register_status = result.get('register_status', '000')
    modified_files = result.get('modified_files', [])

    # 1. Check if application is functional (20 points)
    app_functional = False
    if login_status == '200':
        score += 20
        app_functional = True
        feedback_parts.append("Login page functional (HTTP 200)")
    else:
        feedback_parts.append(f"Login page broken (HTTP {login_status}) - Possible syntax error")

    # 2. Check for security banner (20 points)
    banner_present = False
    if expected_banner in login_body:
        score += 20
        banner_present = True
        feedback_parts.append("Security banner found in HTML")
    else:
        feedback_parts.append("Security banner missing from HTML")

    # 3. Check for View modifications (15 points)
    views_modified = any('resources/views' in f for f in modified_files)
    if views_modified:
        score += 15
        feedback_parts.append("Blade views modified")
    else:
        feedback_parts.append("No Blade views modified")

    # 4. Check for Route modifications (15 points)
    routes_modified = any('routes/web.php' in f for f in modified_files)
    if routes_modified:
        score += 15
        feedback_parts.append("routes/web.php modified")
    else:
        feedback_parts.append("routes/web.php NOT modified")

    # 5. Check if Registration Route is disabled (10 points)
    # If standard Laravel routing is removed/commented, the register URL should 404
    # (or 405/500), but definitely not 200.
    if register_status != '200':
        score += 10
        feedback_parts.append(f"Register route disabled (HTTP {register_status})")
    else:
        feedback_parts.append("Register route is still accessible (HTTP 200)")

    # 6. VLM Trajectory Verification (20 points)
    # Check if the agent actually worked in a code editor / terminal
    vlm_passed = False
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        prompt = """
        You are verifying an AI agent's trajectory. 
        The task was to disable user registration in a PHP/Laravel codebase.
        Did the agent open a terminal or a code editor (like nano, vim, or VS Code) to edit PHP and Blade template files?
        Respond with JSON: {"edited_code": true/false}
        """
        
        vlm_res = query_vlm(images=frames + [final], prompt=prompt)
        vlm_passed = vlm_res.get('parsed', {}).get('edited_code', False)
        
        if vlm_passed:
            score += 20
            feedback_parts.append("VLM: Code editing activity detected")
        else:
            feedback_parts.append("VLM: No clear code editing activity detected")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        feedback_parts.append("VLM verification skipped/failed")

    # Define strict passing criteria:
    # Must have the app working, banner added, and routes modified.
    key_criteria_met = app_functional and banner_present and routes_modified
    
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }