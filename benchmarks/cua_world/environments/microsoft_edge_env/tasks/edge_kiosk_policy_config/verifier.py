#!/usr/bin/env python3
"""
Verifier for Edge Kiosk Policy Configuration Task
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_edge_kiosk_policy(traj, env_info, task_info):
    """
    Verifies that the agent correctly configured Edge enterprise policies.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    metadata = task_info.get('metadata', {})
    expected_policies = metadata.get('expected_policies', {})
    required_blocked = set(metadata.get('required_blocked_domains', []))

    policies = result.get("aggregated_policies", {})
    files_found = result.get("policy_files_found", [])
    report_exists = result.get("report_exists", False)
    report_content = result.get("report_content", "").lower()
    timestamps_valid = result.get("file_timestamps_valid", False)

    score = 0
    feedback = []

    # Criterion 1: Policy File Existence & Validity (10 pts)
    # Must have found at least one valid JSON file created during the task
    valid_files = [f for f in files_found if f.get("valid_json")]
    if valid_files and timestamps_valid:
        score += 10
        feedback.append("Valid policy JSON file(s) created.")
    elif valid_files:
        score += 5
        feedback.append("Policy file exists but timestamp is suspicious (pre-task?).")
    else:
        feedback.append("No valid policy JSON files found in /etc/microsoft-edge/policies/managed/.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    # Criterion 2: Policy Values Check (70 pts total)
    
    # Homepage (10 pts)
    if policies.get("HomepageLocation") == expected_policies["HomepageLocation"]:
        score += 10
        feedback.append("Homepage configured correctly.")
    else:
        feedback.append(f"Homepage incorrect. Found: {policies.get('HomepageLocation')}")

    # New Tab Page (10 pts)
    # Check if URL contains ssa.gov (sometimes policies handle NTP differently)
    ntp = policies.get("NewTabPageLocation", "")
    if "ssa.gov" in ntp:
        score += 10
        feedback.append("New Tab Page configured correctly.")
    else:
        feedback.append(f"New Tab Page incorrect. Found: {ntp}")

    # Blocklist (15 pts)
    # Check if at least 4 of required domains are in the list
    blocklist = policies.get("URLBlocklist", [])
    if isinstance(blocklist, list):
        # Normalize to lower case and simple domain check
        blocked_str = " ".join(blocklist).lower()
        count = 0
        for domain in required_blocked:
            if domain in blocked_str:
                count += 1
        
        if count >= 4:
            score += 15
            feedback.append(f"URL Blocklist sufficient ({count}/{len(required_blocked)} domains).")
        else:
            feedback.append(f"URL Blocklist insufficient. Found {count} required domains.")
    else:
        feedback.append("URLBlocklist is not a list.")

    # Download Restrictions (10 pts)
    if policies.get("DownloadRestrictions") == 3:
        score += 10
        feedback.append("Download restrictions correct (3).")
    else:
        feedback.append(f"DownloadRestrictions incorrect. Found: {policies.get('DownloadRestrictions')}")

    # DevTools (10 pts)
    if policies.get("DeveloperToolsAvailability") == 2:
        score += 10
        feedback.append("DevTools disabled correctly (2).")
    else:
        feedback.append(f"DeveloperToolsAvailability incorrect. Found: {policies.get('DeveloperToolsAvailability')}")

    # InPrivate (10 pts)
    if policies.get("InPrivateModeAvailability") == 1:
        score += 10
        feedback.append("InPrivate mode disabled correctly (1).")
    else:
        feedback.append(f"InPrivateModeAvailability incorrect. Found: {policies.get('InPrivateModeAvailability')}")

    # Boolean/Integer minor policies (5 pts each)
    if policies.get("PasswordManagerEnabled") is False:
        score += 5
        feedback.append("Password Manager disabled.")
    
    if policies.get("BookmarkBarEnabled") is True:
        score += 5
        feedback.append("Bookmark Bar enabled.")

    if policies.get("BrowserSignin") == 0:
        score += 5
        feedback.append("Browser Sign-in disabled.")


    # Criterion 3: Deployment Report (15 pts)
    if report_exists:
        # Check if created after start
        # Timestamps are handled in export script, we assume 'report_mtime' > task_start logic there
        # but let's check simple content heuristic
        mentions = 0
        keywords = ["homepage", "blocklist", "download", "devtools", "private", "password", "sign-in"]
        for k in keywords:
            if k in report_content:
                mentions += 1
        
        if mentions >= 3:
            score += 15
            feedback.append("Deployment report exists and is detailed.")
        else:
            score += 5
            feedback.append("Deployment report exists but lacks detail.")
    else:
        feedback.append("Deployment report not found.")


    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }