#!/usr/bin/env python3
"""
Verifier for add_application_log_source task.

Verification Strategy:
1. Programmatic: Check if 'webserver-01' exists in the EventLog Analyzer database.
2. Anti-Gaming: Ensure the device count increased during the task session.
3. VLM: Verify via trajectory that the agent navigated the UI correctly.
"""

import json
import tempfile
import os
import logging
import sys
# Add parent directory to path to import vlm_utils if needed, though we use gym_anything.vlm usually
# from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_application_log_source(traj, env_info, task_info):
    """
    Verify that the Apache application log source was added.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Metadata expectations
    expected_name = task_info.get('metadata', {}).get('expected_source_name', 'webserver-01')

    # 1. DB Verification (Primary Signal) - 50 points
    source_found = result.get('source_found_in_db', False)
    source_details = result.get('source_details', '')
    
    if source_found:
        score += 50
        feedback_parts.append(f"Success: Source '{expected_name}' found in database configuration.")
        
        # Check if details look correct (case insensitive check for Apache/Web)
        # Note: 'source_details' comes from raw DB row, format usually "id|name|type"
        if "apache" in source_details.lower() or "linux" in source_details.lower():
            score += 10
            feedback_parts.append("Source type appears correct.")
    else:
        feedback_parts.append(f"Failed: Source '{expected_name}' not found in database.")

    # 2. State Change Verification - 20 points
    # Did the number of devices increase?
    count_increase = result.get('count_increase', 0)
    if count_increase > 0:
        score += 20
        feedback_parts.append(f"Device count increased by {count_increase}.")
    elif not source_found:
        feedback_parts.append("No new devices were added.")

    # 3. VLM Verification (Trajectory) - 20 points
    # We check if the agent actually interacted with the "Add New Source" UI
    # This acts as a backup if DB query fails or as confirmation of workflow
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        You are verifying an agent's actions in EventLog Analyzer.
        The goal was to add a new 'Apache' application log source named 'webserver-01'.
        
        Look at these screenshots of the agent's workflow.
        1. Do you see the 'Settings' or 'Log Source' configuration page?
        2. Do you see a form where 'webserver-01' is typed or visible?
        3. Do you see 'Apache' selected as the application type?
        4. Do you see the file path '/home/ga/log_samples/apache_access.log' being entered?
        
        Return JSON: {"evidence_found": boolean, "confidence": "high/medium/low", "reason": "string"}
        """
        
        try:
            vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                if parsed.get('evidence_found'):
                    score += 20
                    feedback_parts.append("VLM confirms workflow execution.")
                else:
                    feedback_parts.append("VLM could not clearly verify workflow details.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # If VLM fails but DB passed, we assume success
            if source_found:
                score += 20
                feedback_parts.append("VLM skipped, but DB check passed.")

    # Final scoring logic
    # Pass if DB confirms source existence OR (Count increased AND VLM confirms workflow)
    passed = False
    if score >= 50 and source_found:
        passed = True
    elif score >= 40 and count_increase > 0 and "VLM confirms" in "".join(feedback_parts):
        passed = True
        feedback_parts.append("(Passed via secondary verification signals)")

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }