#!/usr/bin/env python3
import json
import os
import sys
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_post_insurance_eob(traj, env_info, task_info):
    """
    Verify that an insurance payment of $180.00 with check #556677 was posted for Oliver Queen.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Metadata
    metadata = task_info.get('metadata', {})
    expected_amount = float(metadata.get('payment_amount', 180.00))
    expected_check = metadata.get('check_number', '556677')
    expected_payer = metadata.get('payer_name', 'Star City Health')
    
    # Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # Scoring
    score = 0
    feedback_parts = []
    
    # Database Verification
    billing_records = result.get('billing_records', [])
    payment_records = result.get('payment_records', [])
    all_records = billing_records + payment_records
    
    payment_found = False
    amount_correct = False
    check_correct = False
    payer_correct = False # Harder to verify if field mapping is unknown, usually check # is key
    
    # Logic: Search all records for the payment
    # NOSH payment records typically have negative amounts or separate payment fields
    # We look for the amount 180 (or -180) and check ref 556677
    
    for record in all_records:
        # Check values in all fields to be robust against schema variations
        values = str(record.values())
        
        # Check Check Number
        if expected_check in values:
            check_correct = True
            
            # Check Amount (look for 180.00 or 180)
            # Some systems store payment as 'payment' column, others as 'charge' column with type
            # We look for 180 in specific relevant fields if possible, or broad search
            
            # Convert record values to float if possible to check amount
            record_amount_match = False
            for k, v in record.items():
                try:
                    val_float = float(v)
                    if abs(val_float - expected_amount) < 0.01:
                        record_amount_match = True
                        break
                except:
                    continue
            
            if record_amount_match:
                amount_correct = True
                payment_found = True
                # If we found the record with check and amount, stop
                break
                
    # Score Calculation
    if payment_found:
        score += 30 # Record exists with correct amount
        feedback_parts.append("Payment record found with correct amount.")
    else:
        # Partial credit if check number found but amount wrong
        if check_correct:
            score += 10
            feedback_parts.append(f"Record with check #{expected_check} found, but amount incorrect.")
        else:
            feedback_parts.append(f"No record found with check #{expected_check}.")

    if amount_correct and check_correct:
        score += 40 # High value on exact match
        feedback_parts.append("Check number and amount match exactly.")

    # VLM Verification (Trajectory)
    # Check if agent interacted with billing/payment screens
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        final_screen = get_final_screenshot(traj)
        
        prompt = f"""
        Review these screenshots of an EHR agent.
        Goal: Post an insurance payment of $180.00 with check #{expected_check} from '{expected_payer}'.
        
        1. Did the agent navigate to a Billing or Payment screen?
        2. Is '180.00' visible in a payment field?
        3. Is '{expected_check}' visible in a reference/check number field?
        4. Is '{expected_payer}' visible?
        
        Return JSON: {{ "billing_screen_visited": bool, "details_entered": bool, "confidence": float }}
        """
        
        try:
            vlm_res = query_vlm(images=frames + [final_screen], prompt=prompt)
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('billing_screen_visited'):
                score += 15
                feedback_parts.append("VLM confirmed navigation to billing.")
            if parsed.get('details_entered'):
                score += 15
                feedback_parts.append("VLM confirmed payment details entry.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if DB verified, give full points for visual to avoid penalizing valid headless work? 
            # No, keep it rigorous. If DB is perfect, maybe boost score.
            if payment_found and amount_correct:
                score += 30 # Compensate VLM points if DB is perfect

    # Final Check
    passed = (score >= 70) and payment_found and amount_correct
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback_parts)
    }