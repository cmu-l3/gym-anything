#!/usr/bin/env python3
"""
Verifier for create_event_rule task.

Verifies that the agent created a specific VMS event rule:
- Event: Camera Disconnect
- Action: Show Desktop Notification
- Comment: "Camera Offline Alert"
- Target: All cameras
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_event_rule(traj, env_info, task_info):
    """
    Verify the event rule creation using API data exported from the environment.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_comment = metadata.get('expected_comment', 'Camera Offline Alert')
    
    # 2. Retrieve result data
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

    # 3. Analyze Results
    new_rules = result.get('new_rules', [])
    
    if not new_rules:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No new event rules were created."
        }

    # Find the best matching rule among new rules
    best_score = 0
    best_feedback = []
    
    for rule in new_rules:
        current_score = 0
        current_feedback = []
        
        # Criterion 1: Rule Exists (Implicit if we are iterating)
        current_score += 20
        current_feedback.append("New rule created")

        # Criterion 2: Correct Event Type (25 pts)
        # Nx Witness API uses 'cameraDisconnectEvent'
        event_type = rule.get('eventType', '')
        if 'cameraDisconnectEvent' in event_type:
            current_score += 25
            current_feedback.append("Correct event type (Camera Disconnect)")
        else:
            current_feedback.append(f"Wrong event type: {event_type}")

        # Criterion 3: Correct Action Type (20 pts)
        # Nx Witness API uses 'showPopupAction'
        action_type = rule.get('actionType', '')
        if 'showPopupAction' in action_type:
            current_score += 20
            current_feedback.append("Correct action type (Desktop Notification)")
        else:
            current_feedback.append(f"Wrong action type: {action_type}")

        # Criterion 4: Correct Comment (15 pts)
        comment = rule.get('comment', '')
        if comment == expected_comment:
            current_score += 15
            current_feedback.append("Correct comment")
        elif expected_comment.lower() in comment.lower():
            current_score += 10
            current_feedback.append(f"Comment close match ('{comment}')")
        else:
            current_feedback.append(f"Wrong comment: '{comment}'")

        # Criterion 5: Rule Enabled (10 pts)
        # API usually returns boolean or string "true"
        enabled = rule.get('disabled', False) is False # API often uses 'disabled' field, or 'enabled'. Let's check.
        # Nx Witness V1 rules usually have 'disabled': false means enabled.
        # Or sometimes 'enabled': true. Let's handle both carefully.
        is_disabled = rule.get('disabled', False)
        # If 'enabled' key exists, prioritize it
        if 'enabled' in rule:
            is_enabled = rule.get('enabled')
        else:
            is_enabled = not is_disabled

        if is_enabled:
            current_score += 10
            current_feedback.append("Rule enabled")
        else:
            current_feedback.append("Rule is disabled")

        # Criterion 6: All Cameras Scope (10 pts)
        # eventResourceIds should be empty or null for "All Cameras"
        resources = rule.get('eventResourceIds', [])
        if not resources: # None or empty list
            current_score += 10
            current_feedback.append("Applies to all cameras")
        else:
            current_feedback.append(f"Restricted to specific resources: {resources}")

        # Update best score
        if current_score > best_score:
            best_score = current_score
            best_feedback = current_feedback

    # 4. Final Verification
    passed = best_score >= 65 and "Correct event type" in str(best_feedback) and "Correct action type" in str(best_feedback)
    
    return {
        "passed": passed,
        "score": best_score,
        "feedback": " | ".join(best_feedback)
    }