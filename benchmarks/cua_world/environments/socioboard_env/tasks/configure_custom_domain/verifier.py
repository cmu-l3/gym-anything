#!/usr/bin/env python3
"""
Verifier for configure_custom_domain task.

Verification Strategy:
1. Programmatic Checks (Primary):
   - /etc/hosts updated with social.agency.local -> 127.0.0.1
   - social-agency.conf vhost file created
   - DocumentRoot and ServerName are correct
   - Directory directives (AllowOverride, Require all granted) are present
   - Vhost is enabled via a2ensite
   - Apache config is valid
   - Socioboard .env APP_URL is updated
   - curl http://social.agency.local/ succeeds with Socioboard content
2. VLM Checks (Secondary):
   - Trajectory shows Firefox navigating to social.agency.local
3. Anti-Gaming:
   - Verifies the vhost file was created/modified AFTER the task started.
   - Requires actual HTTP request success to prevent spoofing files without a working server.
"""

import os
import json
import tempfile
import logging

# Ensure gym_anything modules are available for trajectory frame sampling
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    pass

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_custom_domain(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Extract task result JSON
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
    max_score = 100

    # Anti-gaming: File timestamp check
    task_start = result.get('task_start', 0)
    vhost_mtime = result.get('vhost_mtime', 0)
    created_during_task = vhost_mtime >= task_start if vhost_mtime > 0 else False

    # 1. /etc/hosts entry (15 points)
    if result.get('hosts_entry', False):
        score += 15
        feedback_parts.append("/etc/hosts updated")
    else:
        feedback_parts.append("Missing /etc/hosts entry")

    # 2. Vhost File & ServerName (15 points)
    if result.get('vhost_exists', False) and result.get('server_name_ok', False):
        if created_during_task:
            score += 15
            feedback_parts.append("Vhost created correctly")
        else:
            feedback_parts.append("Vhost exists but modified before task start (possible gaming)")
    else:
        feedback_parts.append("Vhost missing or incorrect ServerName")

    # 3. DocumentRoot (10 points)
    if result.get('docroot_ok', False):
        score += 10
        feedback_parts.append("DocumentRoot set correctly")
    else:
        feedback_parts.append("Incorrect/Missing DocumentRoot")

    # 4. Directory Block (5 points)
    if result.get('dir_block_ok', False):
        score += 5
        feedback_parts.append("Directory directives correct")
    else:
        feedback_parts.append("Directory directives missing/incorrect")

    # 5. Vhost Enabled (10 points)
    if result.get('vhost_enabled', False):
        score += 10
        feedback_parts.append("Vhost enabled")
    else:
        feedback_parts.append("Vhost not enabled in Apache")

    # 6. Apache Config Valid (5 points)
    if result.get('apache_valid', False):
        score += 5
        feedback_parts.append("Apache config valid")
    else:
        feedback_parts.append("Apache config invalid")

    # 7. HTTP Success & Content (15 + 10 points) - MANDATORY
    http_success = result.get('http_success', False)
    if http_success:
        score += 15
        feedback_parts.append(f"HTTP response OK ({result.get('http_code')})")
        if result.get('http_content_ok', False):
            score += 10
            feedback_parts.append("Socioboard content verified")
        else:
            feedback_parts.append("HTTP OK but missing expected content")
    else:
        feedback_parts.append(f"HTTP request failed ({result.get('http_code')})")

    # 8. APP_URL in .env updated (10 points)
    if result.get('env_updated', False):
        score += 10
        feedback_parts.append(".env APP_URL updated")
    else:
        feedback_parts.append(".env APP_URL not updated")

    # 9. VLM Visual Check (5 points)
    vlm_points = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        if final_img:
            images_to_check = frames + [final_img]
            prompt = """
            Look at these screenshots of a user's trajectory setting up a web application.
            Does the browser address bar show navigation to `http://social.agency.local` or `social.agency.local`
            while successfully displaying a webpage (not an error page)?
            Respond in JSON format: {"browser_shows_domain": true/false}
            """
            vlm_response = query_vlm(images=images_to_check, prompt=prompt)
            if vlm_response.get('success', False):
                parsed = vlm_response.get('parsed', {})
                if parsed.get('browser_shows_domain', False):
                    vlm_points = 5
                    score += vlm_points
                    feedback_parts.append("VLM verified browser view")
                else:
                    feedback_parts.append("VLM could not verify browser view")
    except Exception as e:
        logger.warning(f"VLM verification skipped/failed: {e}")

    # Determine Pass/Fail
    # To pass, HTTP connectivity *must* be successful (ensures it actually works)
    # and total score must be >= 70
    is_passing = (score >= 70) and http_success and created_during_task

    return {
        "passed": is_passing,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }