#!/usr/bin/env python3
"""
Verifier for configure_automated_broadcast_survey task.

Checks if the Vicidial campaign 'EMRGNCY' was correctly configured 
with the specified survey parameters.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_broadcast_survey(traj, env_info, task_info):
    """
    Verify the broadcast survey configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected = metadata.get('expected_config', {})
    scoring = metadata.get('scoring', {})

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

    # Basic Checks
    if not result.get('state_changed', False):
        return {"passed": False, "score": 0, "feedback": "No changes detected in campaign configuration."}

    config = result.get('config', {})
    score = 0
    feedback_parts = []
    
    # 1. Verify Configuration Fields (Programmatic)
    # Total possible: 100 points based on metadata weights
    
    # Helper to check fields
    def check_field(field_key, display_name):
        actual_val = str(config.get(field_key, "")).strip()
        expected_val = str(expected.get(field_key, "")).strip()
        points = scoring.get(field_key, 0)
        
        if actual_val == expected_val:
            return points, f"{display_name} Correct ({actual_val})"
        else:
            return 0, f"{display_name} Incorrect (Expected: '{expected_val}', Got: '{actual_val}')"

    # Field Checks
    p1, f1 = check_field("survey_first_audio_file", "Audio File")
    score += p1
    feedback_parts.append(f1)

    p2, f2 = check_field("survey_dtmf_digits", "DTMF Digits")
    score += p2
    feedback_parts.append(f2)

    p3, f3 = check_field("survey_ni_digit", "Safety Digit")
    score += p3
    feedback_parts.append(f3)

    p4, f4 = check_field("survey_ni_status", "Safety Status")
    score += p4
    feedback_parts.append(f4)

    p5, f5 = check_field("survey_wait_seconds", "Wait Time")
    score += p5
    feedback_parts.append(f5)

    p6, f6 = check_field("survey_method", "Survey Method")
    score += p6
    feedback_parts.append(f6)

    # For extension, we check survey_extension AND survey_method since method EXTENSION requires an extension
    p7, f7 = check_field("survey_extension", "Extension Number")
    # Only award extension points if Method is also correct or close, but here we treat independently
    score += p7 
    feedback_parts.append(f7)

    p8, f8 = check_field("survey_no_response_action", "No-Response Action")
    score += p8
    feedback_parts.append(f8)

    # 2. VLM Verification (Supplementary)
    # We check if the agent actually navigated to the detail view
    frames = sample_trajectory_frames(traj, n=3)
    final_shot = get_final_screenshot(traj)
    
    vlm_prompt = (
        "Does this screen show the Vicidial Campaign Modify interface? "
        "Can you see a section labeled 'Survey' or 'Survey Settings'? "
        "Does it look like the user is configuring a survey?"
    )
    
    # We don't heavily penalize VLM failure here if DB check passes, 
    # but we use it to confirm the agent was in the right place.
    vlm_result = query_vlm(images=frames + [final_shot], prompt=vlm_prompt)
    
    if vlm_result.get("success"):
        feedback_parts.append("VLM confirmed UI interaction.")
    
    # Final Score Calculation
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }