#!/usr/bin/env python3
"""
Verifier for process_tax_exempt_sale task in Copper POS.

Verifies:
1. Customer "City General Hospital" was created.
2. Transaction exists for this customer.
3. Transaction total is $50.00 and Tax is $0.00.
4. VLM Verification: Uses trajectory to verify the "Tax Exempt" checkbox was clicked 
   and the final receipt/screen showed $0.00 tax.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_process_tax_exempt_sale(traj, env_info, task_info):
    """
    Verify the tax-exempt sale task using file-based logs and VLM.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_tax = metadata.get('expected_tax', 0.0)
    expected_total = metadata.get('expected_total', 50.0)

    # 1. Load File-Based Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result file: {e}")
        result = {}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Criterion 1: Customer Record Found (20 pts)
    if result.get('customer_found_in_db', False):
        score += 20
        feedback.append("Customer 'City General Hospital' found in database.")
    else:
        feedback.append("Customer 'City General Hospital' NOT found in database.")

    # Criterion 2: Transaction Record Found (20 pts)
    if result.get('transaction_found_in_db', False):
        score += 20
        feedback.append("Transaction record found.")
    else:
        feedback.append("Transaction record NOT found.")

    # Criterion 3: Financial Accuracy (30 pts)
    # Check if we detected the tax/total from files
    detected_tax = result.get('detected_tax', -1)
    detected_total = result.get('detected_total', -1)
    
    financials_passed = False
    if detected_tax == expected_tax and detected_total == expected_total:
        score += 30
        financials_passed = True
        feedback.append(f"Financials correct: Tax ${detected_tax}, Total ${detected_total}.")
    elif detected_tax != -1:
        feedback.append(f"Financials incorrect: Found Tax ${detected_tax}, expected ${expected_tax}.")
    else:
        feedback.append("Could not parse financial details from data files.")

    # Criterion 4: VLM Trajectory Verification (30 pts)
    # Essential because file parsing for Copper is heuristic/proprietary.
    # We rely on VLM to visually confirm the "Tax Exempt" check and the $0.00 tax on screen.
    
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
         feedback.append("No trajectory frames available for visual verification.")
    else:
        prompt = """
        You are verifying a Point of Sale task.
        
        Look for these specific events in the sequence of screenshots:
        1. A customer creation screen where "City General Hospital" is entered.
        2. A checkbox labeled "Tax Exempt" (or similar) being checked/selected.
        3. A sales screen showing "Industrial Cleaner" with a Price of $25.00.
        4. A final total or receipt showing "Tax: $0.00" and "Total: $50.00".
        
        Answer JSON:
        {
            "customer_created": boolean,
            "tax_exempt_checked": boolean,
            "zero_tax_visible": boolean,
            "final_total_correct": boolean
        }
        """
        
        try:
            vlm_resp = query_vlm(images=frames, prompt=prompt)
            vlm_data = vlm_resp.get('parsed', {})
            
            vlm_score = 0
            if vlm_data.get('customer_created'): vlm_score += 5
            if vlm_data.get('tax_exempt_checked'): vlm_score += 10
            if vlm_data.get('zero_tax_visible'): vlm_score += 10
            if vlm_data.get('final_total_correct'): vlm_score += 5
            
            score += vlm_score
            feedback.append(f"Visual Verification Score: {vlm_score}/30")
            
            # Fallback: If file parsing failed but VLM confirms visuals, grant partial credit for financials
            if not financials_passed and vlm_data.get('zero_tax_visible') and vlm_data.get('final_total_correct'):
                score += 20
                feedback.append("File parsing failed, but visuals confirm correct financials (+20pts fallback).")
                
        except Exception as e:
            feedback.append(f"VLM analysis failed: {str(e)}")

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }