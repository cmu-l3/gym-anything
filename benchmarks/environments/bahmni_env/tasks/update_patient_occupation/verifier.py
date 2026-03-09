#!/usr/bin/env python3
"""
Verifier for update_patient_occupation task.

Verifies:
1. The 'Occupation' attribute for the specific patient matches 'School Teacher'.
2. The attribute actually changed from the initial 'Unemployed'.
3. VLM verification of the trajectory/final screen.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_patient_occupation(traj, env_info, task_info):
    """
    Verify that the patient occupation was updated correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result Data
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Programmatic Verification
    score = 0
    feedback_parts = []
    
    current_value = result.get('current_value', '')
    initial_value = result.get('initial_value', '')
    target_value = "School Teacher"
    
    # Criterion 1: Value Match (60 pts)
    # Be flexible with case and whitespace
    if current_value and target_value.lower() in current_value.lower():
        score += 60
        feedback_parts.append(f"Occupation updated to '{current_value}' (Matches target)")
    else:
        feedback_parts.append(f"Occupation mismatch: Expected '{target_value}', found '{current_value}'")

    # Criterion 2: Change Detection (30 pts)
    # Ensure it's not still "Unemployed"
    if current_value != initial_value:
        score += 30
        feedback_parts.append("Value successfully modified from initial state")
    else:
        feedback_parts.append("Value unchanged from 'Unemployed'")

    # 3. VLM Verification (10 pts)
    # Check if the agent was actually in the Patient Registration/Dashboard UI
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_ss = get_final_screenshot(traj)
        images = frames + ([final_ss] if final_ss else [])
        
        if images:
            prompt = """
            Review these screenshots of a user interacting with the Bahmni Hospital System.
            
            1. Did the user navigate to a Patient Profile or Registration screen?
            2. Is the text "School Teacher" visible in the final frame?
            
            Return JSON: {"ui_navigated": bool, "value_visible": bool}
            """
            
            try:
                vlm_resp = query_vlm(images=images, prompt=prompt)
                parsed = vlm_resp.get('parsed', {})
                if parsed.get('ui_navigated'):
                    vlm_score += 5
                if parsed.get('value_visible'):
                    vlm_score += 5
                feedback_parts.append(f"VLM verified UI navigation: {parsed.get('ui_navigated')}")
            except Exception as e:
                logger.error(f"VLM error: {e}")
                # Fallback: give points if programmatic success was perfect
                if score == 90:
                    vlm_score = 10
        else:
            feedback_parts.append("No screenshots available for VLM")
    
    score += vlm_score

    # Final Pass Determination
    # Must have at least 90 programmatic points (Value match + Change detected)
    passed = (score >= 90)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }