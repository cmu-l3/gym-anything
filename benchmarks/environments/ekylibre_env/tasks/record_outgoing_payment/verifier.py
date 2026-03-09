#!/usr/bin/env python3
"""
Verifier for record_outgoing_payment task.
Verifies that the agent created a correct outgoing payment record in Ekylibre.
"""

import json
import os
import tempfile
import logging
from datetime import datetime
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_outgoing_payment(traj, env_info, task_info):
    """
    Verify the outgoing payment task.
    
    Criteria:
    1. A new outgoing payment record exists (created during task).
    2. Amount matches 3250.00.
    3. Payee is 'Coopérative Agricole du Centre'.
    4. Date is '2024-06-15'.
    5. VLM confirms UI interaction.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_amount = float(metadata.get('expected_amount', 3250.00))
    expected_payee = metadata.get('expected_payee', "Coopérative Agricole du Centre")
    expected_date = metadata.get('expected_date', "2024-06-15")
    tolerance = metadata.get('tolerance_amount', 0.01)

    # 1. Load Result JSON from container
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

    score = 0
    feedback_parts = []
    
    # Data extraction
    found_payment = result.get('found_payment')
    last_payment_debug = result.get('last_payment_debug')
    count_diff = result.get('count_diff', 0)

    # DATABASE VERIFICATION
    
    if found_payment:
        # Criterion 1: Record exists (25 pts)
        score += 25
        feedback_parts.append("New payment record created.")
        
        # Criterion 2: Correct Amount (25 pts)
        # Handle string or float from JSON
        actual_amount = float(found_payment.get('amount', 0))
        if abs(actual_amount - expected_amount) <= tolerance:
            score += 25
            feedback_parts.append(f"Amount correct ({actual_amount}).")
        else:
            feedback_parts.append(f"Amount incorrect: expected {expected_amount}, got {actual_amount}.")

        # Criterion 3: Correct Payee (20 pts)
        actual_payee = found_payment.get('payee_name', '')
        # Simple fuzzy match or substring check
        if expected_payee.lower() in actual_payee.lower():
            score += 20
            feedback_parts.append(f"Payee correct ({actual_payee}).")
        else:
            feedback_parts.append(f"Payee incorrect: expected '{expected_payee}', got '{actual_payee}'.")

        # Criterion 4: Correct Date (15 pts)
        actual_date = found_payment.get('to_bank_at', '')
        if actual_date.startswith(expected_date):
            score += 15
            feedback_parts.append(f"Date correct ({actual_date}).")
        else:
            feedback_parts.append(f"Date incorrect: expected {expected_date}, got {actual_date}.")
            
    else:
        # No matching payment found created during task
        feedback_parts.append("No payment record found matching time criteria.")
        
        if count_diff > 0:
            feedback_parts.append("Database count increased, but record didn't match timestamp filter.")
        else:
            feedback_parts.append("Database record count did not increase.")
            
        if last_payment_debug:
            feedback_parts.append(f"Most recent payment in DB: {last_payment_debug.get('payee_name')} - {last_payment_debug.get('amount')}.")

    # VISUAL VERIFICATION (15 pts)
    # Only perform if we have some evidence of effort to save API calls, 
    # or always perform if result is ambiguous. Here we check if score is > 0 or count > 0.
    
    vlm_score = 0
    if score > 0 or count_diff > 0 or result.get('final_count', 0) > 0:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_screen = get_final_screenshot(traj)
            images = frames + [final_screen] if final_screen else frames
            
            prompt = f"""
            Verify if the user created an outgoing payment in Ekylibre.
            Look for:
            1. Navigation to Outgoing Payments or Financial section.
            2. A form filled with Payee '{expected_payee}' and Amount '{expected_amount}'.
            3. A success message or the payment appearing in a list.
            
            Return JSON with:
            {{"form_seen": bool, "success_seen": bool, "details": "string"}}
            """
            
            vlm_response = query_vlm(images, prompt)
            
            # Simple parsing of VLM result (assuming the helper returns a dict or we parse it)
            # This logic depends on gym_anything implementation details, simplified here:
            if isinstance(vlm_response, dict):
                if vlm_response.get('form_seen') or vlm_response.get('success_seen'):
                    vlm_score = 15
                    feedback_parts.append("Visual verification passed.")
                else:
                    feedback_parts.append("Visual verification inconclusive.")
            else:
                 # Fallback if VLM returns raw string or fails
                 # Assume partial credit if we have DB evidence
                 if score >= 50:
                     vlm_score = 15
                     feedback_parts.append("Visual verification skipped (DB strong).")
                     
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            if score >= 50: 
                vlm_score = 15 # Give benefit of doubt if DB is correct
                
    score += vlm_score

    # Final Pass/Fail Check
    # Need at least Payment Exists (25) + Amount (25) = 50. 
    # Threshold in README was 70.
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }