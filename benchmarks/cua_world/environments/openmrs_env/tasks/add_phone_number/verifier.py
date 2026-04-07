#!/usr/bin/env python3
"""
Verifier for add_phone_number task (OpenMRS).

Criteria:
1. Database Verification (40 pts):
   - 'Telephone Number' attribute exists for the target patient.
   - Value matches target '555-867-5309' (ignoring format/separators).
   - Timestamp confirms it was created DURING the task (anti-gaming).
   
2. VLM Verification (60 pts):
   - Trajectory shows navigation to 'Edit' registration section.
   - Trajectory shows interaction with phone field.
   - Final state shows success (no error dialogs).

Total: 100 pts. Pass threshold: 60 pts.
"""

import json
import os
import tempfile
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_phone(phone_str):
    """Keep only digits for comparison."""
    if not phone_str:
        return ""
    return re.sub(r'\D', '', str(phone_str))

def verify_add_phone_number(traj, env_info, task_info):
    """
    Verify the agent added the phone number correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Programmatic Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Check 1: Database Evidence (40 pts) ---
    target_digits = task_info.get('metadata', {}).get('target_phone_digits', '5558675309')
    
    phone_found = result_data.get('phone_found', False)
    phone_value = result_data.get('phone_value', "")
    created_during_task = result_data.get('created_during_task', False)
    
    digits_found = normalize_phone(phone_value)
    
    if phone_found:
        if digits_found == target_digits:
            feedback.append("Success: Phone number matches target exactly.")
            # Full points only if created during task
            if created_during_task:
                score += 40
                feedback.append("Anti-gaming check passed: Record created during task.")
            else:
                score += 10
                feedback.append("Warning: Record exists but has old timestamp (pre-dating task).")
        else:
            score += 10
            feedback.append(f"Partial: Phone number found but value differs (Expected digits: {target_digits}, Found: {digits_found}).")
    else:
        feedback.append("Failure: No phone number record found in database.")

    # --- Check 2: VLM Trajectory Verification (60 pts) ---
    # We sample frames to verify the workflow
    frames = sample_trajectory_frames(traj, n=6)
    
    if not frames:
        feedback.append("Warning: No trajectory frames available for visual verification.")
    else:
        prompt = """
        You are verifying an agent's actions in an OpenMRS Electronic Health Record system.
        The goal was to add a phone number to a patient.
        
        Review the sequence of screenshots:
        1. Did the agent open a form or click an 'Edit' button? (Look for modals, forms, or pencil icons being clicked)
        2. Did the agent locate a 'Telephone' or 'Contact' field?
        3. Did the agent type a phone number (specifically 555-867-5309)?
        4. Did the agent save the form (click Confirm/Save)?
        5. Are there any error messages (red text, alerts)?
        
        Answer with JSON:
        {
            "edit_initiated": true/false,
            "phone_field_interaction": true/false,
            "correct_number_visible": true/false,
            "save_action_observed": true/false,
            "errors_present": true/false,
            "confidence": "high/medium/low"
        }
        """
        
        try:
            vlm_response = query_vlm(images=frames, prompt=prompt)
            vlm_result = vlm_response.get('parsed', {})
            
            # Scoring logic for VLM
            if vlm_result.get('edit_initiated'):
                score += 10
                feedback.append("VLM: Edit workflow initiated.")
            
            if vlm_result.get('phone_field_interaction'):
                score += 10
                feedback.append("VLM: Interaction with phone field observed.")
                
            if vlm_result.get('correct_number_visible'):
                score += 20
                feedback.append("VLM: Correct phone number confirmed visually.")
                
            if vlm_result.get('save_action_observed'):
                score += 20
                feedback.append("VLM: Save action observed.")
                
            if vlm_result.get('errors_present'):
                score = max(0, score - 20)
                feedback.append("VLM: Errors detected in UI.")
                
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            feedback.append("VLM verification failed due to internal error.")

    # Final verdict
    passed = (score >= 60) and phone_found and (digits_found == target_digits)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }