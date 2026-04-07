#!/usr/bin/env python3
"""
Verifier for configure_incident_assignment task.

Criteria:
1. Audit Trail CSV exists and was created during the task.
2. Audit Trail CSV contains the rule name 'Critical_Response_Auto'.
3. VLM verification of the UI state (trajectory or agent screenshot) shows the rule configured.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_incident_assignment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    expected_rule_name = metadata.get('rule_name', 'Critical_Response_Auto')
    
    # Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. Verify Audit File (40 points)
    audit_exists = result.get('audit_file_exists', False)
    audit_created = result.get('audit_file_created_during_task', False)
    content_match = result.get('audit_content_match', False)

    if audit_exists and audit_created:
        score += 20
        feedback.append("Audit evidence file exported successfully.")
        
        if content_match:
            score += 20
            feedback.append(f"Audit file contains expected rule name '{expected_rule_name}'.")
        else:
            feedback.append(f"Audit file does NOT contain rule name '{expected_rule_name}'.")
    else:
        feedback.append("Audit evidence file missing or not created during task.")

    # 2. VLM Verification (60 points)
    # Use agent's screenshot if available, otherwise final screenshot, plus trajectory
    
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    # If agent took a specific screenshot of the rule, try to use that
    agent_screenshot_path = result.get('agent_screenshot_path')
    agent_screenshot_exists = result.get('agent_screenshot_exists', False)
    
    images_to_check = frames + [final_shot]
    
    # Try to fetch agent screenshot if it exists
    if agent_screenshot_exists and agent_screenshot_path:
        try:
            temp_ss = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env(agent_screenshot_path, temp_ss.name)
            # We can't easily load this into the VLM helper without PIL, but the 
            # framework's `query_vlm` usually expects bytes or paths it can access.
            # Standard VLM helper usually takes PIL images or bytes.
            # Assuming framework handles standard trajectory images. 
            # We will rely on trajectory frames which are safer.
            os.unlink(temp_ss.name)
        except:
            pass

    prompt = f"""
    You are verifying an EventLog Analyzer task.
    Goal: Create an Incident Assignment Rule named '{expected_rule_name}' assigning 'Critical' incidents to 'admin'.

    Look at the sequence of images.
    1. Do you see a screen listing Incident/Assignment Rules?
    2. Is there a rule named '{expected_rule_name}' visible in the list?
    3. Can you see details showing Severity='Critical' or Assignee='admin'?
    4. Do you see the user exporting a CSV file?

    Answer with JSON:
    {{
        "rule_list_visible": true/false,
        "rule_name_visible": true/false,
        "configuration_correct": true/false,
        "export_action_visible": true/false,
        "confidence": "high/medium/low"
    }}
    """

    vlm_result = query_vlm(images=images_to_check, prompt=prompt)
    
    vlm_score = 0
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        if parsed.get('rule_list_visible'):
            vlm_score += 10
        if parsed.get('rule_name_visible'):
            vlm_score += 30
        if parsed.get('configuration_correct'):
            vlm_score += 10
        if parsed.get('export_action_visible'):
            vlm_score += 10
            
        feedback.append(f"VLM Analysis: {parsed}")
    else:
        feedback.append("VLM verification failed to process images.")

    score += vlm_score

    # Final logic
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }