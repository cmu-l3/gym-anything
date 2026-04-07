#!/usr/bin/env python3
"""
Verifier for edit_feature_attribute task (QField).

Verifies that:
1. The GeoPackage file was modified (timestamp check)
2. The specific attribute for 'Paris' matches the expected string (SQLite check)
3. The agent navigated the UI correctly (VLM trajectory check)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_edit_feature_attribute(traj, env_info, task_info):
    """
    Verify the agent updated the feature attribute correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_value = metadata.get('expected_value', "Telecom assessment complete. 4G coverage confirmed.")
    initial_value = metadata.get('initial_value', "No survey data")

    # ================================================================
    # 1. Retrieve Result Data from Container
    # ================================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task result from device: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # ================================================================
    # 2. Database & File Verification (60 points)
    # ================================================================
    score = 0
    feedback_parts = []
    
    file_modified = result.get('file_modified', False)
    final_value = result.get('final_value', "").strip()
    
    # Check 1: File modification (15 pts)
    if file_modified:
        score += 15
        feedback_parts.append("Database file was saved.")
    else:
        feedback_parts.append("Database file was NOT saved (timestamp unchanged).")

    # Check 2: Value changed from initial (20 pts)
    # This proves they did *something* to the specific record
    if final_value != initial_value:
        score += 20
        feedback_parts.append("Attribute value was modified.")
    else:
        feedback_parts.append(f"Attribute value unchanged ('{final_value}').")

    # Check 3: Exact match (25 pts)
    if final_value == expected_value:
        score += 25
        feedback_parts.append("Text matches exactly.")
    elif expected_value in final_value:
        score += 15
        feedback_parts.append("Text is close/contains expected content.")
    else:
        feedback_parts.append(f"Text incorrect. Expected: '{expected_value}', Got: '{final_value}'")

    # ================================================================
    # 3. VLM Trajectory Verification (40 points)
    # ================================================================
    # We use VLM to verify the workflow steps (Map -> Form -> Edit -> Save)
    frames = sample_trajectory_frames(traj, n=6)
    
    vlm_prompt = """
    You are verifying an agent using QField (GIS app) on Android.
    The goal is to: Select a point on the map, open the attribute form, edit a text field, and save.
    
    Look at the sequence of screenshots and check for:
    1. MAP_INTERACTION: Is a map visible with markers (points)?
    2. FORM_OPEN: Is a feature information or attribute form visible (listing fields like Name, Description)?
    3. EDITING: Is the keyboard visible or is a field being edited?
    4. SAVING: Is a checkmark button or save action visible/clicked?
    
    Return JSON:
    {
        "map_seen": true/false,
        "form_seen": true/false,
        "editing_seen": true/false,
        "save_seen": true/false,
        "confidence": "high/medium/low"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    vlm_score = 0
    
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        if parsed.get('map_seen'): vlm_score += 10
        if parsed.get('form_seen'): vlm_score += 10
        if parsed.get('editing_seen'): vlm_score += 10
        if parsed.get('save_seen'): vlm_score += 10
        
        score += vlm_score
        feedback_parts.append(f"Visual verification score: {vlm_score}/40")
    else:
        feedback_parts.append("Visual verification failed (VLM error).")
        # Fallback: if data is correct, give partial VLM credit
        if final_value == expected_value:
            score += 20
            feedback_parts.append("Granting partial visual credit based on correct data.")

    # ================================================================
    # Final Result
    # ================================================================
    # Pass threshold: 60 points + Data must be modified
    passed = (score >= 60) and (final_value != initial_value)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }