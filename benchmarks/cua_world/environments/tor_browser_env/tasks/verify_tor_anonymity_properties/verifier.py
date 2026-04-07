#!/usr/bin/env python3
"""Verifier for verify_tor_anonymity_properties task.

Verifies the compiled Tor anonymity verification report, checks for correct file
location and expected formatting of IP, SOCKS proxy settings, and Tor browser versions.
Also cross-references places.sqlite for proper page visitation and bookmarking.
"""

import json
import logging
import os
import tempfile
import base64
import re
import ipaddress

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_anonymity_properties(traj, env_info, task_info):
    """
    Verify the agent compiled the Tor anonymity report and visited required pages.

    Scoring (100 points total):
    - File exists exactly at /home/ga/Documents/anonymity-verification.txt (15 pts) [REQUIRED]
    - File is newly created during the task run (10 pts)
    - Valid public IPv4 Exit IP reported (15 pts)
    - Tor Status correctly set to "Connected" (10 pts)
    - SOCKS Proxy correctly configured as 127.0.0.1:<port> (10 pts)
    - Browser identified correctly (5 pts)
    - Version present (5 pts)
    - Verification URL present (5 pts)
    - `check.torproject.org` is in Tor history (10 pts)
    - `check.torproject.org/api/ip` is in Tor history (10 pts)
    - Tor Connection Verifier bookmark exists (5 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r', encoding='utf-8') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Result file not found: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback_parts = []

    # 1. File exists requirement
    file_exists = result.get('file_exists', False)
    if not file_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "File /home/ga/Documents/anonymity-verification.txt NOT found."
        }
    
    score += 15
    feedback_parts.append("File exists (15/15)")

    # 2. File created during task
    if result.get('file_is_new', False):
        score += 10
        feedback_parts.append("File is newly created (10/10)")
    else:
        feedback_parts.append("File predates task start (0/10)")

    # Retrieve and decode file content
    content_b64 = result.get('file_content_b64', '')
    content = ""
    if content_b64:
        try:
            content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
        except Exception:
            pass
    
    # Parse content line by line
    lines = [line.strip() for line in content.split('\n') if line.strip()]
    content_dict = {}
    for line in lines:
        if ':' in line:
            parts = line.split(':', 1)
            content_dict[parts[0].strip().lower()] = parts[1].strip()

    # 3. Exit IP check
    exit_ip = content_dict.get('exit ip', '')
    ip_valid = False
    try:
        ip = ipaddress.ip_address(exit_ip)
        if ip.version == 4 and not ip.is_private and not ip.is_loopback:
            ip_valid = True
    except Exception:
        pass
    
    if ip_valid:
        score += 15
        feedback_parts.append("Valid public Exit IP (15/15)")
    else:
        feedback_parts.append("Exit IP invalid or missing (0/15)")

    # 4. Tor Status check
    status = content_dict.get('tor status', '')
    if 'connected' in status.lower():
        score += 10
        feedback_parts.append("Tor Status 'Connected' (10/10)")
    else:
        feedback_parts.append("Tor Status invalid (0/10)")

    # 5. SOCKS Proxy check
    proxy = content_dict.get('socks proxy', '')
    if '127.0.0.1:' in proxy:
        score += 10
        feedback_parts.append("SOCKS Proxy correct (10/10)")
    else:
        feedback_parts.append("SOCKS Proxy invalid (0/10)")

    # 6. Browser check
    browser = content_dict.get('browser', '')
    if 'tor browser' in browser.lower() or 'firefox' in browser.lower():
        score += 5
        feedback_parts.append("Browser identified (5/5)")
    else:
        feedback_parts.append("Browser invalid (0/5)")

    # 7. Version check
    version = content_dict.get('version', '')
    if re.search(r'\d+\.\d+', version):
        score += 5
        feedback_parts.append("Version present (5/5)")
    else:
        feedback_parts.append("Version missing (0/5)")

    # 8. Verification URL check
    url = content_dict.get('verification url', '')
    if 'check.torproject.org' in url:
        score += 5
        feedback_parts.append("Verification URL correct (5/5)")
    else:
        feedback_parts.append("Verification URL missing (0/5)")

    # 9 & 10. History Check (check.torproject.org and api/ip endpoint)
    if result.get('history_has_check_torproject', False):
        score += 10
        feedback_parts.append("Visited check.torproject.org (10/10)")
    else:
        feedback_parts.append("Did not visit check.torproject.org (0/10)")

    if result.get('history_has_api_ip', False):
        score += 10
        feedback_parts.append("Visited API endpoint (10/10)")
    else:
        feedback_parts.append("Did not visit API endpoint (0/10)")

    # 11. Bookmark Title Check
    if result.get('bookmark_title_correct', False):
        score += 5
        feedback_parts.append("Bookmark correct (5/5)")
    else:
        feedback_parts.append("Bookmark missing/incorrect (0/5)")

    # Pass threshold is 60+ points and file must be created
    passed = score >= 60 and file_exists

    logger.info(f"Task verify_tor_anonymity_properties scored {score}/100")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }