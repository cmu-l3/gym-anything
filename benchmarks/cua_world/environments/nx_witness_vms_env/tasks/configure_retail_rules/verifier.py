#!/usr/bin/env python3
"""
Verifier for configure_retail_rules task.

Verification Strategy:
1. Load the exported Event Rules from the API.
2. Search for the 3 specific rules defined in the task.
3. Verify the properties of each rule (Source, Caption, Action, Target).
4. Verify Soft Trigger configuration.
"""

import json
import os
import sys
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def verify_retail_rules(traj, env_info, task_info):
    """
    Verify the configuration of 3 specific event rules.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    # 1. Retrieve Data from Container
    temp_result_path = "/tmp/local_task_result.json"
    temp_rules_path = "/tmp/local_event_rules.json"
    temp_devices_path = "/tmp/local_devices.json"
    
    try:
        # Get main result file
        copy_from_env("/tmp/task_result.json", temp_result_path)
        with open(temp_result_path, 'r') as f:
            result_data = json.load(f)
            
        # Get exported event rules
        copy_from_env(result_data["event_rules_file"], temp_rules_path)
        with open(temp_rules_path, 'r') as f:
            event_rules = json.load(f)
            
        # Get exported devices (to resolve camera names to IDs)
        copy_from_env(result_data["devices_file"], temp_devices_path)
        with open(temp_devices_path, 'r') as f:
            devices = json.load(f)
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task data: {str(e)}"}
    finally:
        # Cleanup
        for p in [temp_result_path, temp_rules_path, temp_devices_path]:
            if os.path.exists(p):
                os.unlink(p)

    # 2. Map Camera Names to IDs
    entrance_cam_id = None
    for d in devices:
        if d.get("name") == "Entrance Camera":
            entrance_cam_id = d.get("id")
            break
            
    if not entrance_cam_id:
        return {"passed": False, "score": 0, "feedback": "Configuration Error: 'Entrance Camera' not found in system."}

    # 3. Analyze Rules
    # We look for 3 distinct successful configurations
    
    score = 0
    feedback = []
    
    # Flags
    has_void_rule = False
    has_refund_rule = False
    has_silent_alarm = False
    
    # Helper to check string inclusion case-insensitive
    def contains_ignore_case(text, substring):
        return substring.lower() in str(text).lower()

    for rule in event_rules:
        event_type = rule.get("eventType")
        action_type = rule.get("actionType")
        event_condition = rule.get("eventCondition", "") # Contains matcher text
        event_resource_ids = rule.get("eventResourceIds", []) # Soft triggers target this
        action_resource_ids = rule.get("actionResourceIds", []) # Bookmarks target this
        
        # --- Check Rule 1: VOID -> Bookmark ---
        if event_type == "userDefinedEvent" and action_type == "bookmark":
            # Check conditions
            if contains_ignore_case(event_condition, "POS-Register-01") and contains_ignore_case(event_condition, "VOID"):
                # Check target
                if entrance_cam_id in action_resource_ids:
                    has_void_rule = True
                    
        # --- Check Rule 2: REFUND -> Notification ---
        if event_type == "userDefinedEvent" and action_type == "showNotification":
            if contains_ignore_case(event_condition, "POS-Register-01") and contains_ignore_case(event_condition, "REFUND"):
                has_refund_rule = True

        # --- Check Rule 3: Silent Alarm (Soft Trigger) -> Bookmark ---
        if event_type == "softwareTrigger" and action_type == "bookmark":
            # Soft triggers are attached to a camera (eventResourceIds)
            if entrance_cam_id in event_resource_ids:
                # Check name (often in eventCondition or comments depending on version)
                # We check broadly in the rule object string representation for the name
                if contains_ignore_case(str(rule), "Silent Alarm"):
                    has_silent_alarm = True

    # 4. Calculate Score
    
    # Rule 1: Void Tracking (35 pts)
    if has_void_rule:
        score += 35
        feedback.append("✅ POS Void rule configured correctly.")
    else:
        feedback.append("❌ POS Void rule missing or incorrect (Must match 'POS-Register-01' + 'VOID' -> Bookmark on Entrance Camera).")

    # Rule 2: Refund Alert (30 pts)
    if has_refund_rule:
        score += 30
        feedback.append("✅ POS Refund rule configured correctly.")
    else:
        feedback.append("❌ POS Refund rule missing or incorrect (Must match 'POS-Register-01' + 'REFUND' -> Show Notification).")

    # Rule 3: Silent Alarm (35 pts)
    if has_silent_alarm:
        score += 35
        feedback.append("✅ Silent Alarm soft trigger configured correctly.")
    else:
        feedback.append("❌ Silent Alarm soft trigger missing or incorrect (Must be Soft Trigger on Entrance Camera named 'Silent Alarm' -> Bookmark).")

    # 5. Final Determination
    passed = (score >= 90) # Requires all 3 to be substantially correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }