#!/usr/bin/env python3
"""
Verifier for implement_security_analytics_tracking task.

Verification Strategy:
1. HTTP Check for security.txt (Status 200)
2. Content verification of security.txt
3. File creation timestamp check (Anti-gaming)
4. HTTP Check for homepage (Status 200, size > threshold)
5. Content verification of tracking snippet in homepage
6. VLM Trajectory analysis to confirm agent edited files
"""

import os
import json
import base64
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying a computer agent's trajectory for a webmaster task.
The agent was asked to create a security.txt file and inject a tracking snippet into a web application's PHP/HTML code.

Look at these screenshots taken during the task.
1. Do you see the agent using a terminal or a text editor (like nano, vim, or similar) to edit code files?
2. Do you see any indication of navigating directories like /opt/socioboard or editing .blade.php / .php / .txt files?

Respond ONLY with a JSON object:
{
    "edited_files_in_terminal": true/false,
    "reasoning": "Brief explanation of what is visible"
}
"""

def verify_security_analytics_tracking(traj, env_info, task_info):
    """
    Verify that security.txt was created properly and tracking snippet injected,
    while maintaining application health.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_contact = metadata.get('security_contact', 'Contact: mailto:security@socioboard.local')
    expected_expires = metadata.get('security_expires', 'Expires: 2027-12-31T23:59:59.000Z')
    tracking_marker = metadata.get('tracking_marker', 'SOCIOBOARD_CUSTOM_TRACKING_V1')
    min_size = metadata.get('min_homepage_size_bytes', 5000)

    # 1. Retrieve the exported JSON from the environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # 2. Evaluate security.txt criteria
    sec_http = result.get('sec_http_code', '000')
    sec_content_b64 = result.get('sec_content_b64', '')
    sec_created = result.get('sec_created_during_task', False)
    
    try:
        sec_content = base64.b64decode(sec_content_b64).decode('utf-8')
    except Exception:
        sec_content = ""

    if sec_http == "200":
        score += 10
        feedback_parts.append("security.txt accessible (HTTP 200)")
        
        has_contact = expected_contact in sec_content
        has_expires = expected_expires in sec_content
        
        if has_contact and has_expires:
            score += 15
            feedback_parts.append("security.txt content is correct")
        else:
            feedback_parts.append("security.txt missing required lines")
    else:
        feedback_parts.append(f"security.txt not accessible (HTTP {sec_http})")

    if sec_created:
        score += 10
        feedback_parts.append("security.txt created during task")
    else:
        feedback_parts.append("security.txt not created during task (Anti-gaming check failed)")

    # 3. Evaluate Tracking Snippet and App Health criteria
    home_http = result.get('home_http_code', '000')
    home_size = result.get('home_size_bytes', 0)
    tracking_exists = result.get('tracking_exists', False)
    app_healthy = result.get('app_healthy', False)

    app_is_safe = (home_http == "200") and (home_size > min_size) and app_healthy

    if app_is_safe:
        score += 20
        feedback_parts.append(f"App health maintained (HTTP 200, size {home_size} bytes)")
    else:
        feedback_parts.append(f"App health failed (HTTP {home_http}, size {home_size} bytes, healthy={app_healthy})")

    if tracking_exists:
        score += 25
        feedback_parts.append("Tracking snippet successfully injected")
    else:
        feedback_parts.append("Tracking snippet missing from homepage HTML")

    # 4. VLM Trajectory Verification
    # Sample frames to ensure the agent actually worked in the terminal/editor
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        if frames and final_frame:
            vlm_response = query_vlm(images=frames + [final_frame], prompt=VLM_PROMPT)
            if vlm_response.get('success'):
                parsed = vlm_response.get('parsed', {})
                if parsed.get('edited_files_in_terminal', False):
                    score += 20
                    feedback_parts.append("VLM verified code editing trajectory")
                else:
                    feedback_parts.append("VLM did not observe code editing in trajectory")
            else:
                feedback_parts.append("VLM query failed")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        feedback_parts.append("VLM verification skipped/errored")

    # Determine pass/fail
    # Max score = 10 (sec http) + 15 (sec content) + 10 (sec created) + 20 (app health) + 25 (tracking) + 20 (vlm) = 100
    # Must have both main elements functional
    key_criteria_met = (sec_http == "200") and tracking_exists and app_is_safe
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }