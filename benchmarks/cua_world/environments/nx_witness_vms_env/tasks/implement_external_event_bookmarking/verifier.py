#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_external_event_bookmarking(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Created the correct Generic Event rule.
    2. Successfully simulated the event to create a bookmark.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    analysis = result.get("analysis", {})
    rules_data = result.get("rules_data", [])
    target_camera_id = result.get("target_camera_id", "")
    
    score = 0
    feedback_parts = []
    
    # Criteria 1: Event Rule Created (40 pts) & Logic Correct (20 pts)
    # We re-verify the raw rules data here to be robust
    rule_found = False
    rule_logic_correct = False
    
    for rule in rules_data:
        # Check Type
        if rule.get('eventType') != 'software.nx.event.generic':
            continue
            
        # Check Action
        if rule.get('actionType') != 'cameraBookmark':
            continue
            
        # Check Condition (Source/Caption)
        # Nx Witness stores these in 'eventCondition' or 'params' usually encoded
        # We search string representation for robustness across versions
        rule_str = json.dumps(rule)
        if 'AI_Analytics' in rule_str and 'Loitering_Detected' in rule_str:
            rule_found = True
            
            # Check Target Camera
            # The target is usually in 'actionParams' -> 'resourceIds'
            # or 'actionResourceIds'
            action_params = json.dumps(rule.get('actionParams', {}))
            action_resources = json.dumps(rule.get('actionResourceIds', []))
            
            if target_camera_id in action_params or target_camera_id in action_resources:
                rule_logic_correct = True
                break
    
    if rule_found:
        score += 40
        feedback_parts.append("Generic Event Rule created.")
        if rule_logic_correct:
            score += 20
            feedback_parts.append("Rule logic (Source/Caption/Target) is correct.")
        else:
            feedback_parts.append("Rule exists but target camera or parameters incorrect.")
    else:
        feedback_parts.append("No valid Generic Event rule found matching 'AI_Analytics' and 'Loitering_Detected'.")

    # Criteria 2: Bookmark Exists (40 pts)
    # This proves the agent actually triggered the API
    bookmark_found = analysis.get("found_valid_bookmark", False)
    
    if bookmark_found:
        score += 40
        feedback_parts.append("Simulation successful: Bookmark created via API.")
    else:
        feedback_parts.append("Simulation failed: No matching bookmark found on the camera timeline.")

    # Pass Threshold
    passed = score >= 80  # Requires Rule + Logic + Bookmark OR Rule + Bookmark (if logic check is fuzzy)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }