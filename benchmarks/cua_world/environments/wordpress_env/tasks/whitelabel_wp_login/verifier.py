#!/usr/bin/env python3
"""
Verifier for White-Label WordPress Login task.

Verification Strategy (Programmatic + VLM on Trajectory):

Programmatic checks (100 points) — from export script JSON inside container:
  1. mu-plugins directory and PHP file exist (10 pts)
  2. Logo Link URL Modified (30 pts)
  3. Background Color CSS Modified (30 pts)
  4. Custom Logo CSS Modified (30 pts)

VLM checks (Optional cross-validation):
  5. Process verification: Frames show editing PHP files and viewing login page.
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    if not image and not images:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None

TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent completing a WordPress white-label task.

For successful completion, the agent should:
1. Navigate to /var/www/html/wordpress/wp-content and create mu-plugins folder.
2. Edit a PHP file to inject CSS and hooks.
3. View the WordPress login page (wp-login.php) in the browser to test changes.

Assess:
1. WORKFLOW_COMPLETED: Did the agent write PHP code and check the browser?
2. CODE_EDITOR_VISIBLE: Is a code editor or terminal visible with PHP hook code?
3. BROWSER_TESTED: Did the agent view the wp-login.php page in the browser?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "code_editor_visible": true/false,
    "browser_tested": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

def verify_whitelabel_wp_login(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0

    # Read result json
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/whitelabel_wp_login_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Read HTML file
    temp_html = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    html_content = ""
    try:
        copy_from_env("/tmp/wp_login_html.txt", temp_html.name)
        with open(temp_html.name, 'r', encoding='utf-8', errors='ignore') as f:
            html_content = f.read()
    except Exception as e:
        logger.warning(f"Failed to read HTML file: {e}")
    finally:
        if os.path.exists(temp_html.name):
            os.unlink(temp_html.name)

    # 1. mu-plugins directory and PHP file (10 points)
    if result.get("mu_plugins_exists") and result.get("php_file_exists"):
        score += 10
        feedback_parts.append("mu-plugins and PHP file exist")
    else:
        feedback_parts.append("mu-plugins directory or PHP file missing")

    html_lower = html_content.lower()

    # 2. Logo Link URL Modified (30 points)
    link_correct = False
    
    # Try finding the link inside <div id="login">
    match = re.search(r'<div\s+id="login".*?<h1>\s*<a\s+href="([^"]+)"', html_lower, re.DOTALL)
    if match:
        href = match.group(1)
        if "wordpress.org" not in href and ("localhost" in href or href == "/" or href == "http://localhost/"):
            link_correct = True
    elif result.get("logo_link_localhost"):
        link_correct = True

    if link_correct:
        score += 30
        feedback_parts.append("Logo link updated to homepage")
    else:
        feedback_parts.append("Logo link not updated correctly")

    # 3. Background Color CSS (30 points)
    bg_color_correct = False
    if "#1e293b" in html_lower or "rgb(30, 41, 59)" in html_lower or "1e293b" in html_lower:
        bg_color_correct = True

    if bg_color_correct:
        score += 30
        feedback_parts.append("Background color updated")
    else:
        feedback_parts.append("Background color not updated to #1e293b")

    # 4. Custom Logo CSS (30 points)
    logo_correct = False
    if "client-logo.png" in html_lower:
        logo_correct = True

    if logo_correct:
        score += 30
        feedback_parts.append("Custom logo injected")
    else:
        feedback_parts.append("Custom logo (client-logo.png) not found in login page")

    # Optional VLM checks
    query_vlm = env_info.get("query_vlm")
    if query_vlm and traj:
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            vlm_res = _vlm_query(query_vlm, TRAJECTORY_PROCESS_PROMPT, images=frames)
            if vlm_res:
                if vlm_res.get("workflow_completed") and vlm_res.get("code_editor_visible"):
                    feedback_parts.append("VLM confirmed coding workflow")
                else:
                    feedback_parts.append("VLM did not clearly observe coding workflow")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }