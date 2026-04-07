#!/usr/bin/env python3
"""
Verifier for CAMEO Data Manager Task: Register Transport Route.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_register_transport_route(traj, env_info, task_info):
    """
    Verifies that the transportation route was correctly registered in CAMEO Data Manager.
    
    Verification Logic:
    1. Check if the record exists in the internal database (via export_result.json).
    2. Verify specific fields (Name, Type, Description, Comments).
    3. Verify that the database was actually modified during the task (anti-gaming).
    4. Use VLM to confirm the UI state and data entry workflow.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', 'Norfolk Southern - Heartland Corridor')
    expected_type = metadata.get('expected_type', 'Rail')
    
    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: export_result.ps1 saves to C:\workspace\task_result.json
        # The container path mapping usually handles drive letters or we use absolute path
        # In this env, C:\workspace mapped to /workspace usually
        copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        result = {}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. Database Verification (Primary)
    record_found = result.get('record_found', False)
    record_details = result.get('record_details', {})
    db_modified = result.get('db_modified_during_task', False)
    
    if record_found:
        score += 30
        feedback.append("Success: Route record found in database.")
        
        # Check Name (Exact match required by query, but double check)
        actual_name = record_details.get('RouteName', '')
        if actual_name == expected_name:
            score += 10
        
        # Check Type
        actual_type = str(record_details.get('Type', '') or '')
        if expected_type.lower() in actual_type.lower():
            score += 20
            feedback.append(f"Success: Route type '{actual_type}' matches expected '{expected_type}'.")
        else:
            feedback.append(f"Issue: Route type '{actual_type}' does not match expected '{expected_type}'.")
            
        # Check Description
        actual_desc = str(record_details.get('Description', '') or '')
        if "double-stack" in actual_desc.lower() or "intermodal" in actual_desc.lower():
            score += 15
            feedback.append("Success: Description contains key details.")
        else:
            feedback.append("Issue: Description missing keywords (double-stack/intermodal).")

        # Check Comments
        actual_comments = str(record_details.get('Comments', '') or '')
        if "chlorine" in actual_comments.lower():
            score += 15
            feedback.append("Success: Comments mention Chlorine hazard.")
        else:
            feedback.append("Issue: Comments do not mention Chlorine.")
            
    else:
        feedback.append("Fail: No matching record found in the database.")
        
        # Fallback: If DB query failed (e.g. schema mismatch), relying purely on VLM later
        if result.get('record_details', {}).get('error'):
            feedback.append(f"(DB Query Error: {result['record_details']['error']})")

    # Anti-gaming check
    if db_modified:
        score += 10
        feedback.append("Verification: Database file modified during task.")
    elif record_found:
        feedback.append("Warning: Record found but database timestamp didn't update (could be cached or pre-existing).")

    # 3. VLM Verification (Trajectory & Visuals)
    frames = sample_trajectory_frames(traj, n=4)
    final_screenshot = get_final_screenshot(traj)
    
    images_to_check = frames + ([final_screenshot] if final_screenshot else [])
    
    if images_to_check:
        prompt = f"""
        Analyze these screenshots of CAMEO Data Manager.
        The user is supposed to create a new Transport Route.
        
        Look for:
        1. The 'Routes' or 'Transportation' module being open.
        2. Data entry of '{expected_name}'.
        3. Selection of 'Rail' as the type.
        4. Text entry mentioning 'Chlorine' or 'double-stack'.
        
        Did the user appear to complete these steps?
        """
        
        try:
            vlm_res = query_vlm(prompt=prompt, images=images_to_check)
            if vlm_res.get('success'):
                # If DB failed but VLM looks good, give partial credit
                if not record_found and "yes" in vlm_res.get('response', '').lower():
                    score += 30
                    feedback.append("VLM Verification: Visual evidence suggests task completion despite DB verification failure.")
                elif record_found and "yes" in vlm_res.get('response', '').lower():
                    # Bonus/Confirmation
                    pass
                else:
                    feedback.append(f"VLM Analysis: {vlm_res.get('response')}")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")

    # Final Score Calculation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }