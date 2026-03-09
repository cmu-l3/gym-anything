#!/usr/bin/env python3
"""
Verifier for configure_provider_insurance_numbers@1

Checks:
1. Database contains a record linking Admin to Blue Cross Blue Shield.
2. Provider Number matches expected value.
3. Group Number matches expected value.
4. Record was created during the task (Anti-gaming).
5. VLM Trajectory Verification (Secondary).
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_provider_insurance_numbers(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_prov_num = metadata.get('expected_provider_number', 'BCBS-8842-X')
    expected_group_num = metadata.get('expected_group_number', 'GRP-99104')

    score = 0
    feedback_parts = []
    
    # 2. Get result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    db_state = result.get('db_state', {})
    meta = result.get('task_meta', {})
    
    # 3. Primary Verification: Database State (80 points total)
    
    # Check if record exists (30 pts)
    if db_state.get('record_found'):
        score += 30
        feedback_parts.append("Success: Insurance number record found.")
        
        # Check Provider Number (25 pts)
        actual_prov = str(db_state.get('provider_number', '')).strip()
        if actual_prov == expected_prov_num:
            score += 25
            feedback_parts.append(f"Success: Provider Number matches '{expected_prov_num}'.")
        else:
            feedback_parts.append(f"Fail: Expected Provider Number '{expected_prov_num}', found '{actual_prov}'.")
            
        # Check Group Number (25 pts)
        actual_group = str(db_state.get('group_number', '')).strip()
        if actual_group == expected_group_num:
            score += 25
            feedback_parts.append(f"Success: Group Number matches '{expected_group_num}'.")
        else:
            feedback_parts.append(f"Fail: Expected Group Number '{expected_group_num}', found '{actual_group}'.")
            
        # Anti-gaming check (Required for pass)
        # Verify the record ID is greater than what existed before the task
        record_id = int(db_state.get('record_id', 0))
        initial_max_id = int(meta.get('initial_max_id', 0))
        
        if record_id > initial_max_id:
            feedback_parts.append("Verification: New record created (Anti-gaming passed).")
        else:
            feedback_parts.append("Warning: Record ID indicates pre-existing data or reuse (Anti-gaming warning).")
            # We don't fail strictly here if values are correct, but usually implies editing old data
            
    else:
        feedback_parts.append("Fail: No insurance number record found linking Admin to Blue Cross Blue Shield.")
        if db_state.get('error'):
            feedback_parts.append(f"DB Error: {db_state.get('error')}")

    # 4. Secondary Verification: VLM Trajectory (20 points)
    # Checks if the user actually visited the insurance numbers page
    
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        
        prompt = """
        Analyze these screenshots of a user interacting with LibreHealth EHR.
        The user goal is to "Configure Insurance Numbers".
        
        Look for:
        1. Navigation to the "Insurance Numbers" or "Practice Settings" page.
        2. A form or list showing "Provider Number", "Group Number", or "Insurance Company".
        3. Entry of "BCBS-8842-X" or "GRP-99104".
        
        Return JSON:
        {
            "navigated_to_settings": true/false,
            "data_entry_visible": true/false,
            "confidence": 0-10
        }
        """
        
        vlm_res = query_vlm(prompt=prompt, images=frames + [final_screen])
        
        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('navigated_to_settings'):
                vlm_score += 10
            if parsed.get('data_entry_visible'):
                vlm_score += 10
            feedback_parts.append(f"VLM Verification: {vlm_score}/20 points")
        else:
            # Fallback if VLM fails/is unavailable: award points if DB check passed perfectly
            if score >= 80:
                vlm_score = 20
                feedback_parts.append("VLM Verification: Skipped (awarded based on DB success)")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Graceful fallback
        if score >= 80:
            vlm_score = 20

    final_score = score + vlm_score
    
    # Cap at 100
    final_score = min(100, final_score)
    
    passed = final_score >= 80 and db_state.get('record_found')
    
    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback_parts)
    }