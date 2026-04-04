#!/usr/bin/env python3
"""
Verifier for register_prohibited_software task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_register_prohibited_software(traj, env_info, task_info):
    """
    Verifies that uTorrent and Steam are registered as Prohibited and notification is enabled.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Extract data
    software_list = result.get("software_found", [])
    if software_list is None: software_list = []
    
    notification_status = str(result.get("notification_enabled", "false")).lower()
    
    # Helper to find software in list
    def find_software(name):
        for sw in software_list:
            if sw.get("name", "").lower() == name.lower():
                return sw
        return None

    # Check uTorrent (Target 1)
    utorrent = find_software("uTorrent")
    if utorrent:
        score += 20
        feedback.append("uTorrent registered.")
        
        # Check Type
        if "prohibited" in str(utorrent.get("type", "")).lower():
            score += 15
            feedback.append("uTorrent marked as Prohibited.")
        else:
            feedback.append(f"uTorrent type incorrect: {utorrent.get('type', 'None')}")
            
        # Check Manufacturer
        if "bittorrent" in str(utorrent.get("manufacturer", "")).lower():
            score += 5
            feedback.append("uTorrent manufacturer correct.")
    else:
        feedback.append("uTorrent NOT found in database.")

    # Check Steam (Target 2)
    steam = find_software("Steam")
    if steam:
        score += 20
        feedback.append("Steam registered.")
        
        # Check Type
        if "prohibited" in str(steam.get("type", "")).lower():
            score += 15
            feedback.append("Steam marked as Prohibited.")
        else:
            feedback.append(f"Steam type incorrect: {steam.get('type', 'None')}")

        # Check Manufacturer
        if "valve" in str(steam.get("manufacturer", "")).lower():
            score += 5
            feedback.append("Steam manufacturer correct.")
    else:
        feedback.append("Steam NOT found in database.")

    # Check Notification Rule
    # Status in DB is typically 'true'/'false' string or boolean
    if notification_status in ['true', '1', 'enabled']:
        score += 20
        feedback.append("Prohibited software notification enabled.")
    else:
        feedback.append("Prohibited software notification NOT enabled.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }