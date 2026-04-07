#!/usr/bin/env python3
"""
Verifier for configure_investigation_browser task.
Validates Tor browser configuration, history visits, and filesystem report output.
"""

import json
import logging
import os
import tempfile
import base64

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TASK_NAME = "configure_investigation_browser"

def verify_configure_investigation_browser(traj, env_info, task_info):
    """
    Verification strategy (100 points total, 10 points each):
    1. Cookie exception: courtlistener.com ALLOW (type=1)
    2. Cookie exception: opencorporates.com ALLOW (type=1)
    3. Cookie exception: archive.org ALLOW (type=1)
    4. Popup exception: courtlistener.com ALLOW (type=1)
    5. dom.webnotifications.enabled = false
    6. Homepage set to blank page (browser.startup.page=0 OR homepage="about:blank")
    7. check.torproject.org in history [REQUIRED GATE]
    8. courtlistener.com in history
    9. investigation_prep.txt exists, size >= 50, and created after task start
    10. investigation_prep.txt has all valid content keywords
    
    Pass Threshold: >= 50 points AND check.torproject.org is in browser history.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env(f"/tmp/{TASK_NAME}_result.json", tmp.name)
        with open(tmp.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Result file not found: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback_parts = []
    
    # -------------------------------------------------------------
    # Helper to check permissions
    # -------------------------------------------------------------
    perms = result.get('permissions', [])
    def check_perm(domain, perm_type, expected_val):
        for p in perms:
            # Match partial domain to handle "https://courtlistener.com" and "https://www.courtlistener.com"
            if domain in p.get('origin', '') and p.get('type') == perm_type:
                if str(p.get('permission')) == str(expected_val):
                    return True
        return False

    # 1. Cookie exception: courtlistener.com
    if check_perm("courtlistener.com", "cookie", 1):
        score += 10
        feedback_parts.append("Cookie exception: courtlistener ALLOW (10/10)")
    else:
        feedback_parts.append("Missing Cookie exception: courtlistener ALLOW (0/10)")

    # 2. Cookie exception: opencorporates.com
    if check_perm("opencorporates.com", "cookie", 1):
        score += 10
        feedback_parts.append("Cookie exception: opencorporates ALLOW (10/10)")
    else:
        feedback_parts.append("Missing Cookie exception: opencorporates ALLOW (0/10)")

    # 3. Cookie exception: archive.org
    if check_perm("archive.org", "cookie", 1):
        score += 10
        feedback_parts.append("Cookie exception: archive.org ALLOW (10/10)")
    else:
        feedback_parts.append("Missing Cookie exception: archive.org ALLOW (0/10)")

    # 4. Popup exception: courtlistener.com
    if check_perm("courtlistener.com", "popup", 1):
        score += 10
        feedback_parts.append("Popup exception: courtlistener ALLOW (10/10)")
    else:
        feedback_parts.append("Missing Popup exception: courtlistener ALLOW (0/10)")

    # -------------------------------------------------------------
    # Check Preferences
    # -------------------------------------------------------------
    prefs = result.get('prefs', {})
    
    # 5. webnotifications
    if prefs.get("webnotifications_enabled") == "false":
        score += 10
        feedback_parts.append("webnotifications disabled (10/10)")
    else:
        feedback_parts.append("webnotifications NOT disabled (0/10)")
        
    # 6. Homepage blank
    startup_page = prefs.get("startup_page")
    startup_homepage = prefs.get("startup_homepage")
    if startup_page == "0" or startup_homepage == "about:blank":
        score += 10
        feedback_parts.append("Homepage set to blank (10/10)")
    else:
        feedback_parts.append("Homepage NOT set to blank (0/10)")

    # -------------------------------------------------------------
    # Check History
    # -------------------------------------------------------------
    history = result.get('history', [])
    def check_history(domain):
        for url in history:
            if domain in url:
                return True
        return False

    # 7. check.torproject.org (GATE)
    visited_tor_check = check_history("check.torproject.org")
    if visited_tor_check:
        score += 10
        feedback_parts.append("Visited check.torproject.org (10/10)")
    else:
        feedback_parts.append("Did NOT visit check.torproject.org [REQUIRED] (0/10)")

    # 8. courtlistener.com
    if check_history("courtlistener.com"):
        score += 10
        feedback_parts.append("Visited courtlistener.com (10/10)")
    else:
        feedback_parts.append("Did NOT visit courtlistener.com (0/10)")

    # -------------------------------------------------------------
    # Check File
    # -------------------------------------------------------------
    report = result.get('report_file', {})
    file_exists = report.get('exists', False)
    file_size = report.get('size', 0)
    file_mtime = report.get('mtime', 0)
    task_start_ts = result.get('task_start_ts', 0)
    
    # 9. File exists, >= 50 bytes, modified during task
    if file_exists and file_size >= 50 and file_mtime >= task_start_ts:
        score += 10
        feedback_parts.append(f"Report file valid and created/modified during task ({file_size} bytes) (10/10)")
    else:
        if not file_exists:
            feedback_parts.append("Report file missing (0/10)")
        elif file_size < 50:
            feedback_parts.append(f"Report file too small ({file_size} bytes) (0/10)")
        else:
            feedback_parts.append("Report file was not created/modified during task session (0/10)")

    # 10. File Content
    content_valid = False
    if file_exists and report.get('content_b64'):
        try:
            content = base64.b64decode(report['content_b64']).decode('utf-8', errors='ignore').lower()
            
            # Must contain 'tor' AND one of the confirmation words
            has_tor = "tor" in content
            has_confirmation = any(word in content for word in ["active", "confirmed", "connected", "verified"])
            
            # Must contain the three domains
            has_domains = all(domain in content for domain in ["courtlistener", "opencorporates", "archive.org"])
            
            if has_tor and has_confirmation and has_domains:
                content_valid = True
        except Exception as e:
            logger.warning(f"Error decoding file content: {e}")

    if content_valid:
        score += 10
        feedback_parts.append("Report file content matches requirements (10/10)")
    elif file_exists:
        feedback_parts.append("Report file content missing required keywords (0/10)")
    else:
        feedback_parts.append("Report file content check skipped (0/10)")

    # -------------------------------------------------------------
    # Calculate Final Pass/Fail
    # -------------------------------------------------------------
    passed = (score >= 50) and visited_tor_check
    
    # Add trajectory checks using VLM for robust validation
    # If the user did nothing, the programmatic anti-gaming checks catch it via timestamps and missing DB records.
    # The VLM is highly recommended by framework to verify visual trajectory.
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        
        if frames and final_img:
            vlm_prompt = (
                "Did the user use Tor Browser to browse websites or navigate Settings / about:config? "
                "Answer YES if Tor browser UI was actively used during the trajectory, otherwise NO."
            )
            vlm_response = query_vlm(images=frames + [final_img], prompt=vlm_prompt)
            if vlm_response and "YES" not in vlm_response.upper() and score >= 50:
                logger.warning("Programmatic score passed but VLM did not detect Tor Browser usage. Flagging for review.")
    except Exception as e:
        logger.info(f"VLM trajectory validation skipped/failed: {e}")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }