#!/usr/bin/env python3
"""
Verifier for configure_incident_trigger task.

Verifies that a 'Soft Trigger' event rule has been created for the 'Entrance Camera'
that creates a 'Bookmark' with specific text.
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_incident_trigger(traj, env_info, task_info):
    """
    Verify the existence and configuration of the Soft Trigger rule.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    rules = result.get("eventRules", [])
    target_camera_id = result.get("target_camera_id", "")
    app_running = result.get("app_running", False)

    if not rules:
        return {"passed": False, "score": 0, "feedback": "No event rules found in system."}

    # Task Requirements
    REQ_TRIGGER_NAME = "Flag Suspect"
    REQ_BOOKMARK_TEXT = "Suspicious Activity"
    REQ_EVENT_TYPE = "softwareTrigger"  # Soft Trigger
    REQ_ACTION_TYPE = "bookmarkLog"     # Create Bookmark (API name)

    # Scoring Variables
    score = 0
    feedback_parts = []
    
    best_rule_score = 0
    best_rule_feedback = ""

    # Iterate through all rules to find the best match
    for rule in rules:
        current_rule_score = 0
        current_feedback = []

        # 1. Check Event Type (Soft Trigger) - 30 pts
        event_type = rule.get("eventType", "")
        if event_type == REQ_EVENT_TYPE:
            current_rule_score += 30
            current_feedback.append("Correct event type (Soft Trigger)")
        else:
            continue # If it's not a soft trigger, it's not relevant

        # 2. Check Resource (Entrance Camera) - 20 pts
        # eventResourceIds is a list of IDs
        resources = rule.get("eventResourceIds", [])
        if target_camera_id in resources:
            current_rule_score += 20
            current_feedback.append("Correct camera assigned")
        elif not resources:
             # Global trigger? (Usually soft triggers require a resource)
             pass
        else:
             current_feedback.append("Wrong camera assigned")

        # 3. Check Trigger Name ("Flag Suspect") - 10 pts
        # Stored in eventCondition string (e.g., "{"caption":"Flag Suspect",...}")
        event_condition = rule.get("eventCondition", "")
        if REQ_TRIGGER_NAME.lower() in event_condition.lower():
            current_rule_score += 10
            current_feedback.append(f"Correct trigger name ('{REQ_TRIGGER_NAME}')")

        # 4. Check Action Type (Bookmark) - 20 pts
        action_type = rule.get("actionType", "")
        if action_type == REQ_ACTION_TYPE:
            current_rule_score += 20
            current_feedback.append("Correct action (Create Bookmark)")
        elif action_type == "showPopup":
             current_feedback.append("Wrong action (Show Notification instead of Bookmark)")

        # 5. Check Bookmark Text ("Suspicious Activity") - 20 pts
        # Stored in actionParams string
        action_params = rule.get("actionParams", "")
        if REQ_BOOKMARK_TEXT.lower() in action_params.lower():
            current_rule_score += 20
            current_feedback.append(f"Correct bookmark title ('{REQ_BOOKMARK_TEXT}')")

        # Update best match
        if current_rule_score > best_rule_score:
            best_rule_score = current_rule_score
            best_rule_feedback = ", ".join(current_feedback)

    # Final Evaluation
    passed = best_rule_score >= 80
    
    final_feedback = f"Best matching rule score: {best_rule_score}/100. Details: {best_rule_feedback}"
    if not best_rule_feedback:
        final_feedback = "No Soft Trigger rules found."

    return {
        "passed": passed,
        "score": best_rule_score,
        "feedback": final_feedback
    }