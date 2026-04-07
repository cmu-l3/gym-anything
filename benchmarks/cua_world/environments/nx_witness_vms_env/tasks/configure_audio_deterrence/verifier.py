#!/usr/bin/env python3
"""
Verifier for configure_audio_deterrence task.
Checks if a valid Event Rule exists connecting Motion on Camera X -> Play Sound on Camera X.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_audio_deterrence(traj, env_info, task_info):
    """
    Verify the audio deterrence event rule configuration.
    """
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract configuration data
    target_camera_id = result.get('target_camera_id', '')
    event_rules = result.get('event_rules', [])
    
    if not target_camera_id:
        return {"passed": False, "score": 0, "feedback": "Verification failed: Target camera ID could not be determined."}

    # 3. Scoring Logic
    # We look for the BEST matching rule and score based on that.
    
    best_rule_score = 0
    best_rule_feedback = "No matching event rules found."
    
    # Expected values
    EXPECTED_EVENT = "cameraMotionEvent"
    EXPECTED_ACTION = "playSoundAction"
    EXPECTED_INTERVAL = 60
    TOLERANCE = 10  # Allow 50-70 seconds
    
    matching_rules = []

    for rule in event_rules:
        # Skip disabled rules? Or penalize them.
        # Nx Witness rules have a 'disabled' boolean field usually.
        # If the API doesn't return it, assume enabled.
        is_disabled = rule.get('disabled', False)
        
        rule_score = 0
        feedback_parts = []
        
        # 1. Check Event Type (20 pts)
        if rule.get('eventType') == EXPECTED_EVENT:
            rule_score += 20
            feedback_parts.append("Correct event type (Motion)")
        else:
            feedback_parts.append(f"Wrong event: {rule.get('eventType')}")

        # 2. Check Action Type (20 pts)
        if rule.get('actionType') == EXPECTED_ACTION:
            rule_score += 20
            feedback_parts.append("Correct action type (Play Sound)")
        else:
            feedback_parts.append(f"Wrong action: {rule.get('actionType')}")

        # 3. Check Source Resource (Target Camera) (20 pts)
        # eventResourceIds is a list of IDs. Should contain our camera.
        source_ids = rule.get('eventResourceIds', [])
        if target_camera_id in source_ids:
            rule_score += 20
            feedback_parts.append("Correct trigger source")
        elif not source_ids:
            # Empty usually means "All Cameras" - partial credit?
            # Task asked specifically for Loading Dock Camera.
            rule_score += 5
            feedback_parts.append("Trigger set to 'All Cameras' (should be specific)")
        else:
            feedback_parts.append("Wrong trigger source")

        # 4. Check Target Resource (Target Camera) (20 pts)
        # actionResourceIds is a list of IDs. Should contain our camera.
        target_ids = rule.get('actionResourceIds', [])
        # Note: playSoundAction usually targets the camera to play sound ON.
        if target_camera_id in target_ids:
            rule_score += 20
            feedback_parts.append("Correct sound output target")
        else:
            feedback_parts.append("Wrong sound output target")

        # 5. Check Aggregation/Interval (20 pts)
        # aggregationPeriod is in seconds
        interval = rule.get('aggregationPeriod', 0)
        if abs(interval - EXPECTED_INTERVAL) <= TOLERANCE:
            rule_score += 20
            feedback_parts.append(f"Correct interval ({interval}s)")
        elif interval == 0:
            feedback_parts.append("Interval not set (Continuous)")
        else:
            rule_score += 5 # Partial for setting SOMETHING
            feedback_parts.append(f"Wrong interval ({interval}s)")

        # Penalty for disabled
        if is_disabled:
            rule_score = max(0, rule_score - 20)
            feedback_parts.append("Rule is DISABLED")

        # Combine feedback
        full_feedback = "; ".join(feedback_parts)
        
        # Keep track of the best attempt
        if rule_score > best_rule_score:
            best_rule_score = rule_score
            best_rule_feedback = full_feedback

    # 4. Final Result
    passed = best_rule_score >= 80  # Threshold from task description
    
    return {
        "passed": passed,
        "score": best_rule_score,
        "feedback": best_rule_feedback
    }