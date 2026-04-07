#!/usr/bin/env python3
"""
Verifier for configure_secure_dns_doh task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_secure_dns_doh(traj, env_info, task_info):
    """
    Verifies that the agent configured DoH correctly.
    
    Scoring:
    - DoH Mode Enabled (30 pts): dns_over_https.mode == "secure"
    - Provider Configured (30 pts): dns_over_https.templates contains Cloudflare
    - Verification Screenshot (25 pts): File exists and created during task
    - Status Report (15 pts): File exists and contains correct text
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
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
    feedback = []

    # 1. Verify DoH Mode (30 pts)
    # The mode should be "secure" (which corresponds to "Choose a service provider" enabled state in some versions,
    # or explicitly enforcing it). "automatic" is default. "secure" usually implies strict/explicit.
    # Note: Edge might use 'automatic' if just the toggle is on, but specifying a provider usually sets it to 'secure' or populates templates.
    # We check if templates are populated as the primary signal for "Choose a provider".
    doh_mode = result.get('doh_mode', '')
    doh_templates = result.get('doh_templates', '')

    # If the user selected a specific provider, mode usually becomes 'secure' or remains 'automatic' but with templates.
    # However, strictly enforcing "secure" might be specific to "Strict" settings. 
    # Key check: Did they select Cloudflare?
    
    # Check Provider (30 pts)
    # Cloudflare template usually looks like "https://chrome.cloudflare-dns.com/dns-query"
    if "cloudflare" in doh_templates.lower() or "1.1.1.1" in doh_templates:
        score += 30
        feedback.append("Cloudflare DoH provider configured (30/30).")
    else:
        feedback.append(f"Cloudflare provider NOT found in settings. Templates: '{doh_templates}' (0/30).")

    # Check Mode (30 pts)
    # If they turned the toggle ON, mode is typically 'secure' or 'automatic' with templates. 
    # We give points if mode is NOT 'off' AND templates are set.
    if doh_mode != "off" and doh_templates:
        score += 30
        feedback.append(f"Secure DNS is enabled (Mode: {doh_mode}) (30/30).")
    else:
        feedback.append(f"Secure DNS appears disabled (Mode: {doh_mode}) (0/30).")

    # 2. Verify Screenshot (25 pts)
    if result.get('screenshot_exists') and result.get('screenshot_valid_time'):
        score += 25
        feedback.append("Verification screenshot created (25/25).")
    elif result.get('screenshot_exists'):
        score += 10 # Partial credit if timestamp matches old file (unlikely given setup clears it)
        feedback.append("Screenshot exists but timestamp issue (10/25).")
    else:
        feedback.append("No verification screenshot found (0/25).")

    # 3. Verify Status File (15 pts)
    content = result.get('status_file_content', '').lower()
    if result.get('status_file_exists') and "yes" in content and "doh" in content:
        score += 15
        feedback.append("Status report correct (15/15).")
    elif result.get('status_file_exists'):
        score += 5
        feedback.append("Status report exists but content mismatch (5/15).")
    else:
        feedback.append("Status report not found (0/15).")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }