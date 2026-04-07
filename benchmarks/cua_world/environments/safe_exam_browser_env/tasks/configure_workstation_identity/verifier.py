#!/usr/bin/env python3
"""
Verifier for configure_workstation_identity task.
Checks if the agent successfully updated the SEB configuration attributes in the database.
Also uses VLM on trajectory frames to verify UI navigation.
"""

import json
import tempfile
import os
import logging

from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_workstation_identity(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Error: copy_from_env function not available"}

    metadata = task_info.get('metadata', {})
    expected_width = metadata.get('expected_width', '1280')
    expected_height = metadata.get('expected_height', '800')
    expected_ua = metadata.get('expected_user_agent_suffix', ' SEB_Lab3_Station')
    expected_view_modes = metadata.get('expected_view_mode_values', ['1', 'window', 'Window'])

    # 1. Retrieve the exported JSON result from the environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        if os.path.getsize(temp_result.name) == 0:
            return {"passed": False, "score": 0, "feedback": "Exported result file is empty."}
            
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    attributes = result.get('attributes', {})
    config_id = result.get('config_id')
    
    if not config_id:
        return {"passed": False, "score": 0, "feedback": "Failed to find the target configuration 'Engineering Final Exam 2026'."}

    # 2. Score Database Attributes
    
    # Check Browser View Mode (1 = Window, usually)
    view_mode = attributes.get('browserViewMode', str(attributes.get('browserViewMode', '')))
    if str(view_mode).lower() in [v.lower() for v in expected_view_modes]:
        score += 20
        feedback_parts.append("View Mode set to Window")
    else:
        feedback_parts.append(f"View Mode incorrect (found '{view_mode}')")

    # Check Window Width
    width = attributes.get('mainBrowserWindowWidth', str(attributes.get('mainBrowserWindowWidth', '')))
    if str(width) == expected_width:
        score += 20
        feedback_parts.append("Window Width correct")
    else:
        feedback_parts.append(f"Window Width incorrect (found '{width}')")

    # Check Window Height
    height = attributes.get('mainBrowserWindowHeight', str(attributes.get('mainBrowserWindowHeight', '')))
    if str(height) == expected_height:
        score += 20
        feedback_parts.append("Window Height correct")
    else:
        feedback_parts.append(f"Window Height incorrect (found '{height}')")

    # Check User Agent Suffix
    ua_suffix = attributes.get('userAgentAppend', attributes.get('userAgentSuffix', ''))
    if ua_suffix == expected_ua:
        score += 20
        feedback_parts.append("User Agent Suffix correct")
    elif ua_suffix.strip() == expected_ua.strip() and ua_suffix != "":
        score += 10
        feedback_parts.append("User Agent Suffix missing leading space (partial credit)")
    else:
        feedback_parts.append(f"User Agent Suffix incorrect (found '{ua_suffix}')")

    # 3. Trajectory VLM Verification (20 points)
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        all_frames = frames + [final_frame] if final_frame else frames
        
        if all_frames:
            prompt = (
                "You are evaluating an agent configuring Safe Exam Browser Server. "
                "Did the agent navigate to the 'Exam Configuration' section, open 'Engineering Final Exam 2026', "
                "and interact with the 'User Interface' or 'Network' settings tabs? "
                "Reply with a JSON containing {\"interacted_with_settings\": true/false}"
            )
            vlm_res = query_vlm(images=all_frames, prompt=prompt)
            if vlm_res and isinstance(vlm_res, dict):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('interacted_with_settings'):
                    vlm_score = 20
                    feedback_parts.append("VLM verified trajectory navigation")
                else:
                    feedback_parts.append("VLM could not verify UI interaction")
            else:
                vlm_score = 10  # Give partial credit if VLM fails to parse
                feedback_parts.append("VLM parsing failed")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        vlm_score = 10  # Fallback points if VLM errors out
        feedback_parts.append("VLM check bypassed")

    score += vlm_score

    # Evaluate Pass/Fail
    # To pass, all critical DB attributes must be perfectly set (80 points)
    critical_db_score = score - vlm_score
    passed = critical_db_score >= 80

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }