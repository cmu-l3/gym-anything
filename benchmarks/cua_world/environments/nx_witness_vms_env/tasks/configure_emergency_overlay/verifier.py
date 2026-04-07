#!/usr/bin/env python3
import json
import os
import sys
import tempfile

def verify_configure_emergency_overlay(traj, env_info, task_info):
    """
    Verify the creation of the Emergency Lockdown Soft Trigger rule.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract analysis
    analysis = result.get('api_analysis', {})
    if not analysis or analysis.get('error'):
        return {"passed": False, "score": 0, "feedback": f"API Analysis failed: {analysis.get('error')}"}

    rule_found = analysis.get('rule_found', False)
    details = analysis.get('details', {})
    
    # Scoring criteria
    score = 0
    feedback = []

    if not rule_found:
        return {"passed": False, "score": 0, "feedback": "No event rule found matching 'Lockdown' criteria."}

    # 1. Rule Created (Basic check passed by rule_found)
    score += 20
    feedback.append("Event Rule created.")

    # 2. Trigger Type & Action Type 
    # (Implicitly checked by the filter in export_result.sh which looked for softwareTriggerEvent + showTextOverlayAction)
    score += 40
    feedback.append("Correct Trigger (Soft Trigger) and Action (Text Overlay) types.")

    # 3. Check Trigger Name
    trigger_name = details.get('trigger_name', '')
    if "activate lockdown" in trigger_name.lower():
        score += 20
        feedback.append(f"Correct trigger name: '{trigger_name}'.")
    else:
        feedback.append(f"Incorrect trigger name: '{trigger_name}' (expected 'Activate Lockdown').")

    # 4. Check Action Text
    action_text = details.get('action_text', '')
    if "security alert: lockdown" in action_text.lower():
        score += 10
        feedback.append(f"Correct overlay text: '{action_text}'.")
    else:
        feedback.append(f"Incorrect overlay text: '{action_text}' (expected 'SECURITY ALERT: LOCKDOWN').")

    # 5. Check Duration
    duration = details.get('duration', 0)
    if duration >= 5000:
        score += 10
        feedback.append(f"Correct duration: {duration}ms.")
    else:
        feedback.append(f"Duration too short: {duration}ms (expected >= 5000ms).")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }