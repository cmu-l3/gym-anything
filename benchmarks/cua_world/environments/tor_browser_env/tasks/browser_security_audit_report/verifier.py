#!/usr/bin/env python3
"""Verifier for browser_security_audit_report task.

Verifies that the agent successfully navigated the internal browser pages
and external verification service to compile an accurate text report.
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TASK_NAME = "browser_security_audit_report"

def verify_browser_security_audit_report(traj, env_info, task_info):
    """
    Scoring (100 points total):
    1. File exists & modified after start (10 pts)
    2. Contains all 5 required section headers (15 pts)
    3. Contains valid version number (10 pts)
    4. Contains User Agent string (10 pts)
    5. NoScript documented (10 pts)
    6. Security Level reported correctly (10 pts)
    7. HTTPS-Only Mode reported (10 pts)
    8. Tor Network Connectivity (Yes/No) (10 pts)
    9. Exit IP reported (10 pts)
    10. check.torproject.org found in history (5 pts)

    Pass threshold: 60+ points AND file exists.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
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
    
    # 1. File exists & is new
    file_exists = result.get('file_exists', False)
    file_is_new = result.get('file_is_new', False)
    file_size = result.get('file_size', 0)
    
    if not file_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Report file /home/ga/Documents/tor-audit-report.txt was not created."
        }
        
    if file_is_new and file_size > 50:
        score += 10
        feedback_parts.append("File exists and was created during task (10/10)")
    else:
        feedback_parts.append("File exists but is too small or predates task start (0/10)")

    content = result.get('file_content', '')
    
    # 2. Contains all 5 required section headers
    headers = [
        "--- Application Info ---",
        "--- Installed Extensions ---",
        "--- Security Settings ---",
        "--- Tor Network Verification ---",
        "--- Audit Metadata ---"
    ]
    found_headers = sum(1 for h in headers if h in content)
    if found_headers == len(headers):
        score += 15
        feedback_parts.append("All 5 section headers found (15/15)")
    else:
        partial = int((found_headers / len(headers)) * 15)
        score += partial
        feedback_parts.append(f"{found_headers}/5 headers found ({partial}/15)")

    # 3. Contains valid version number (e.g., 14.0.4, 15.0)
    if re.search(r'(?i)version:?\s*\d+\.\d+(\.\d+)?', content):
        score += 10
        feedback_parts.append("Version number documented (10/10)")
    else:
        feedback_parts.append("Version number missing (0/10)")

    # 4. Contains User Agent string
    if re.search(r'(?i)user agent:?\s*.*Mozilla', content):
        score += 10
        feedback_parts.append("User Agent string documented (10/10)")
    else:
        feedback_parts.append("User Agent missing or incomplete (0/10)")

    # 5. NoScript documented
    if re.search(r'(?i)noscript', content):
        score += 10
        feedback_parts.append("NoScript extension documented (10/10)")
    else:
        feedback_parts.append("NoScript not mentioned (0/10)")

    # 6. Security Level reported
    if re.search(r'(?i)security level:?\s*(standard|safer|safest)', content):
        score += 10
        feedback_parts.append("Security level documented (10/10)")
    else:
        feedback_parts.append("Security level missing (0/10)")

    # 7. HTTPS-Only Mode reported
    if re.search(r'(?i)https-only( mode)?:?\s*(enabled|disabled|true|false)', content):
        score += 10
        feedback_parts.append("HTTPS-Only Mode documented (10/10)")
    else:
        feedback_parts.append("HTTPS-Only Mode missing (0/10)")

    # 8. Tor Network Connectivity
    if re.search(r'(?i)tor connected:?\s*(yes|no|true|false)', content):
        score += 10
        feedback_parts.append("Tor connectivity status documented (10/10)")
    else:
        feedback_parts.append("Tor connectivity status missing (0/10)")

    # 9. Exit IP reported
    # Look for a general IPv4/IPv6 pattern or "not available"
    if re.search(r'(?i)exit ip:?\s*(\d{1,3}(\.\d{1,3}){3}|[a-f0-9:]+|not available)', content):
        score += 10
        feedback_parts.append("Exit IP documented (10/10)")
    else:
        feedback_parts.append("Exit IP missing (0/10)")

    # 10. check.torproject.org found in history
    if result.get('history_has_check_tor', False):
        score += 5
        feedback_parts.append("Visited check.torproject.org (5/5)")
    else:
        feedback_parts.append("check.torproject.org NOT in history (0/5)")

    passed = score >= 60 and file_exists

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }