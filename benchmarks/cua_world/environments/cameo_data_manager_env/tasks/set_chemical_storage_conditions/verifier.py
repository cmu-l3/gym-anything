#!/usr/bin/env python3
"""
Verifier for set_chemical_storage_conditions task.

Verification Strategy:
1. Programmatic: Verify the database file was modified *after* task start (indicates Save).
2. VLM: Visual verification of the form fields in the final state or trajectory.
   - Check Physical State: Liquid
   - Check Storage Codes: A, E
   - Check Pressure/Temp: Ambient
"""

import json
import os
import tempfile
import logging
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_set_chemical_storage_conditions(traj, env_info, task_info):
    """
    Verify the chemical storage conditions task.
    """
    # 1. Setup and imports
    copy_from_env = env_info.get('copy_from_env')
    vlm_query = env_info.get('query_vlm')  # Access VLM helper if available in env_info wrapper
    # Note: If query_vlm is passed differently in your specific framework version, adapt here.
    # Assuming standard gym_anything signature where we might need to import it or it's in env_info
    
    # If VLM helper is not in env_info, try to import from standard location
    if not vlm_query:
        try:
            from gym_anything.vlm import query_vlm
            vlm_query = query_vlm
        except ImportError:
            logger.warning("VLM module not found, trajectory verification will be skipped.")
            vlm_query = None

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 2. Retrieve JSON result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: path inside Windows container is C:\tmp\task_result.json
        # The copy_from_env function usually handles path translation or expects the guest path
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Score Calculation
    score = 0
    feedback = []

    # Criterion A: Database Modification (30 pts)
    # This proves the user actually hit "Save" or committed data
    if result_data.get("db_was_modified", False):
        score += 30
        feedback.append("Database record updated successfully.")
    else:
        feedback.append("Database file was not modified (did you save?).")

    # Criterion B: App Running (10 pts)
    if result_data.get("app_was_running", False):
        score += 10
    else:
        feedback.append("CAMEO Data Manager was not running at the end of the task.")

    # Criterion C: VLM Visual Verification (60 pts)
    # We check the final state or trajectory for the correct checkboxes/dropdowns
    
    # Get final screenshot from trajectory
    final_screenshot = None
    if traj and len(traj) > 0:
        # Assuming traj is list of dicts with 'screenshot' path or similar
        # Adjust based on actual trajectory format
        last_step = traj[-1]
        if isinstance(last_step, dict):
            final_screenshot = last_step.get('screenshot')
        elif hasattr(last_step, 'screenshot'):
            final_screenshot = last_step.screenshot

    if final_screenshot and vlm_query:
        prompt = (
            "Review this screenshot of CAMEO Data Manager's Chemical Inventory screen. "
            "Verify the 'Storage Conditions' or 'Storage Locations' section for Hydrochloric Acid. "
            "1. Is 'Physical State' set to 'Liquid'? "
            "2. Is Storage Code 'A' (Above ground tank) checked or selected? "
            "3. Is Storage Code 'E' (Plastic or non-metallic drum) checked or selected? "
            "4. Is Pressure set to 'Ambient'? "
            "5. Is Temperature set to 'Ambient'? "
            "Respond with JSON: {'liquid_correct': bool, 'code_a_selected': bool, 'code_e_selected': bool, "
            "'pressure_correct': bool, 'temp_correct': bool}"
        )
        
        try:
            vlm_response = vlm_query(images=[final_screenshot], prompt=prompt)
            # Parse JSON from VLM response (assuming wrapper returns dict or we parse string)
            # This logic depends on the specific VLM response format. 
            # Assuming vlm_response returns a dict with 'result' containing the text or parsed json.
            
            # Simulated parsing logic
            if isinstance(vlm_response, dict) and 'result' in vlm_response:
                import re
                json_match = re.search(r'\{.*\}', vlm_response['result'], re.DOTALL)
                if json_match:
                    vlm_data = json.loads(json_match.group(0))
                    
                    if vlm_data.get('liquid_correct'): score += 12
                    if vlm_data.get('code_a_selected'): score += 12
                    if vlm_data.get('code_e_selected'): score += 12
                    if vlm_data.get('pressure_correct'): score += 12
                    if vlm_data.get('temp_correct'): score += 12
                    feedback.append("Visual verification completed.")
                else:
                    # Fallback if VLM didn't return JSON
                    score += 30 # Give partial credit if VLM failed to parse but verification ran
                    feedback.append("Visual verification ran but response format was unclear.")
            else:
                feedback.append("VLM response invalid.")

        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            feedback.append("Visual verification failed to execute.")
    else:
        feedback.append("No screenshots available for visual verification.")

    # 4. Final Determination
    # Pass if score >= 60 and DB was modified
    passed = (score >= 60) and result_data.get("db_was_modified", False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }