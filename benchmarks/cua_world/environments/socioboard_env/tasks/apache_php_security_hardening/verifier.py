#!/usr/bin/env python3
"""
Verifier for apache_php_security_hardening task.

Verification Strategy:
1. Programmatic HTTP Check:
   - Server header must not contain OS (Ubuntu) or exact versions (2.4.x).
   - X-Powered-By header must be completely absent (PHP hidden).
   - /test_indexes/ must return 403 Forbidden (or 404), not 200 OK with a file listing.
2. Health Check:
   - Apache must still be running and serving the homepage (200 or 30x).
3. VLM Trajectory (Anti-Gaming):
   - Check if the agent actually used a terminal/editor during the task to make these changes.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are auditing a DevOps agent completing a server security task.
Look at these screenshot frames from the agent's session.
Did the agent use a terminal or a text editor (like nano, vim, or gedit) to modify configuration files?

Respond in JSON format:
{
    "terminal_or_editor_used": true/false,
    "reasoning": "brief explanation"
}"""

def verify_security_hardening(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ================================================================
    # 1. Read exported programmatic data
    # ================================================================
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
    max_score = 100

    # Extract metrics
    server_header = result.get("server_header", "")
    x_powered_by = result.get("x_powered_by_header", "")
    idx_code = result.get("test_indexes_code", 0)
    idx_body = result.get("test_indexes_body_snippet", "")
    home_code = result.get("home_code", 0)
    apache_running = result.get("apache_running", False)

    logger.info(f"Server Header: {server_header}")
    logger.info(f"X-Powered-By Header: {x_powered_by}")
    logger.info(f"Index Code: {idx_code}")
    logger.info(f"Home Code: {home_code}, Apache Running: {apache_running}")

    # ================================================================
    # CRITERION 1: Apache Version Hidden (25 points)
    # Target: ServerTokens Prod -> Header should just be "Apache"
    # ================================================================
    if server_header == "":
        score += 25
        feedback_parts.append("Server header completely hidden (+25)")
    elif server_header.strip().lower() == "apache":
        score += 25
        feedback_parts.append("Server header correctly masked to 'Apache' (+25)")
    elif "ubuntu" not in server_header.lower() and not any(char.isdigit() for char in server_header):
        score += 20
        feedback_parts.append("Server header partially masked (+20)")
    else:
        feedback_parts.append(f"Server header leaking info: '{server_header}' (0/25)")

    # ================================================================
    # CRITERION 2: PHP Version Hidden (25 points)
    # Target: expose_php = Off -> Header absent
    # ================================================================
    if x_powered_by == "":
        score += 25
        feedback_parts.append("X-Powered-By header successfully removed (+25)")
    elif "php" not in x_powered_by.lower():
        score += 15
        feedback_parts.append("X-Powered-By header modified but present (+15)")
    else:
        feedback_parts.append(f"PHP version still exposed: '{x_powered_by}' (0/25)")

    # ================================================================
    # CRITERION 3: Directory Browsing Disabled (30 points)
    # Target: Options -Indexes -> 403 Forbidden
    # ================================================================
    if idx_code in [403, 404]:
        score += 30
        feedback_parts.append(f"Directory browsing prevented (Status: {idx_code}) (+30)")
    elif "Index of" not in idx_body:
        # Sometimes apps intercept with a 200 OK custom page, which is fine if no file listing is shown
        score += 30
        feedback_parts.append("Directory listing content not found (+30)")
    else:
        feedback_parts.append(f"Directory browsing still active (Status: {idx_code}) (0/30)")

    # ================================================================
    # CRITERION 4: Service Operational / Health Check (10 points)
    # Agent shouldn't break the webserver to "secure" it
    # ================================================================
    web_healthy = False
    if apache_running and home_code in [200, 301, 302]:
        score += 10
        web_healthy = True
        feedback_parts.append("Apache is running and healthy (+10)")
    else:
        feedback_parts.append("Web server is down or broken! (0/10)")
        # Critical failure penalization
        score = min(score, 40)
        feedback_parts.append("PENALTY: Site broken, max score capped.")

    # ================================================================
    # CRITERION 5: VLM Trajectory Verification (10 points)
    # Ensures they actually worked in the system
    # ================================================================
    vlm_passed = False
    try:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            vlm_result = query_vlm(images=frames, prompt=VLM_PROMPT)
            parsed = vlm_result.get("parsed", {})
            if parsed.get("terminal_or_editor_used", False):
                score += 10
                vlm_passed = True
                feedback_parts.append("VLM verified terminal usage (+10)")
            else:
                feedback_parts.append("VLM did not detect terminal usage (0/10)")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        # Give benefit of doubt if VLM fails but file modifications were detected programmatically
        if result.get("security_conf_modified_during_task") or result.get("php_ini_modified_during_task"):
            score += 10
            feedback_parts.append("File modification timestamps proved work (+10)")

    # Final logic
    key_criteria_met = (server_header.lower() == "apache" or x_powered_by == "") and idx_code in [403, 404]
    passed = score >= 80 and web_healthy and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }