#!/usr/bin/env python3
"""Verifier for delete_impound_reason task."""

import json
import tempfile
import os
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

def verify_delete_impound_reason(traj, env_info, task_info):
    """
    Verify that the impound reason 'Obstructing Machinery' was deleted.
    
    Criteria:
    1. Target record 'Obstructing Machinery' is gone from database (50 pts)
    2. Total record count decreased by exactly 1 (30 pts)
    3. Other records still exist (table not wiped) (10 pts)
    4. VLM/Trajectory confirms Admin Panel/Data Manager navigation (10 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/delete_impound_reason_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # Criterion 1: Target Removed (50 pts)
    if result.get('target_removed', False):
        score += 50
        feedback_parts.append("Target impound reason removed")
    else:
        feedback_parts.append("Target impound reason still exists")
        
    # Criterion 2: Count Decreased (30 pts)
    initial = int(result.get('initial_count', 0))
    current = int(result.get('current_count', 0))
    
    if current == initial - 1:
        score += 30
        feedback_parts.append("Record count decreased by 1")
    elif current < initial - 1:
        score += 10
        feedback_parts.append(f"Count decreased by {initial - current} (too many deletions)")
    elif current == initial:
        feedback_parts.append("Record count unchanged")
    else:
        feedback_parts.append("Record count increased")
        
    # Criterion 3: Data Integrity (10 pts)
    if int(result.get('other_records_count', 0)) > 0:
        score += 10
        feedback_parts.append("Other impound reasons preserved")
    else:
        feedback_parts.append("Warning: All impound reasons appear to be deleted")

    # Criterion 4: VLM Trajectory Check (10 pts)
    # We check if the agent visited the Data Manager / Impound Reasons page
    query_vlm = env_info.get('query_vlm')
    vlm_score = 0
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            
            prompt = """
            Analyze these screenshots of a dispatch system admin interface.
            
            Look for evidence of:
            1. The 'Admin Panel' or 'Data Manager' being open.
            2. A list of 'Impound Reasons' or similar configuration data.
            3. An action to delete or remove an item.
            
            Did the user navigate to the Impound Reasons manager?
            Respond with JSON: {"navigated_to_impound_manager": boolean}
            """
            
            # We use the frames to check workflow
            response = query_vlm(images=frames + [final], prompt=prompt)
            if response.get('parsed', {}).get('navigated_to_impound_manager', False):
                vlm_score = 10
                feedback_parts.append("Visual evidence of Data Manager navigation")
            else:
                feedback_parts.append("No visual evidence of Impound Manager access")
        except Exception as e:
            # Fallback if VLM fails: if score is already high (80+), give benefit of doubt
            if score >= 80:
                vlm_score = 10
                feedback_parts.append("Implicit workflow verification (success implied)")
    else:
        # If no VLM, grant points if primary task succeeded
        if score >= 80:
            vlm_score = 10
            
    score += vlm_score

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }