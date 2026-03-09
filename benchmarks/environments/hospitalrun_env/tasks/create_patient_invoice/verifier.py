#!/usr/bin/env python3
"""
Verifier for create_patient_invoice task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_patient_invoice(traj, env_info, task_info):
    """
    Verify that a new invoice was created for Maria Santos with the correct line items.
    
    Scoring:
    - Invoice exists and count increased: 25 pts
    - Correct patient (Maria Santos): 25 pts
    - Line item 1 (X-Ray) present and correct: 25 pts
    - Line item 2 (Office Visit) present and correct: 25 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Load expected data from metadata
    metadata = task_info.get('metadata', {})
    expected_patient = metadata.get('patient_name', "Maria Santos")
    expected_patient_id = metadata.get('patient_id', "P00003")
    
    # Fetch result from container
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
            
    # Initialize scoring
    score = 0
    feedback = []
    
    # 1. Check Invoice Creation
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    invoices = result.get('invoices', [])
    
    if current_count <= initial_count and not invoices:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No invoices found or invoice count did not increase."
        }
        
    # Find the matching invoice
    # We look for ANY invoice that matches the criteria, assuming the agent created one.
    # If multiple exist, we take the best match.
    best_invoice = None
    best_score = -1
    
    for inv in invoices:
        inv_score = 0
        inv_feedback = []
        
        # Check Patient
        patient_ref = inv.get('patient', '')
        raw_data = json.dumps(inv.get('raw_data', {})).lower()
        
        patient_match = False
        if expected_patient_id in patient_ref:
            patient_match = True
        elif expected_patient.lower() in raw_data:
            patient_match = True
        elif "santos" in raw_data and "maria" in raw_data:
            patient_match = True
            
        if patient_match:
            inv_score += 25
            inv_feedback.append("Correct patient linked")
        
        # Check Line Items
        items = inv.get('line_items', [])
        found_xray = False
        found_visit = False
        
        for item in items:
            name = item.get('name', '').lower()
            qty = item.get('quantity', 0)
            
            # Check for X-Ray
            if ("x-ray" in name or "chest" in name) and not found_xray:
                found_xray = True
                if int(qty) == 1:
                    inv_score += 25
                    inv_feedback.append("X-Ray item correct")
                else:
                    inv_score += 15
                    inv_feedback.append(f"X-Ray found but wrong quantity ({qty})")
            
            # Check for Office Visit
            if ("office visit" in name or "level 3" in name) and not found_visit:
                found_visit = True
                if int(qty) == 1:
                    inv_score += 25
                    inv_feedback.append("Office Visit item correct")
                else:
                    inv_score += 15
                    inv_feedback.append(f"Office Visit found but wrong quantity ({qty})")
        
        # If invoice created but no items correct, give base points for creation
        if inv_score == 0 and patient_match:
            inv_score += 25 # Base points for creating invoice for correct patient
        elif not patient_match and (found_xray or found_visit):
            inv_score += 25 # Base points for creating invoice with correct items (wrong patient)
            
        if inv_score > best_score:
            best_score = inv_score
            best_invoice = inv
            feedback = inv_feedback

    # Final Evaluation
    if best_invoice:
        # Add base points for invoice existence if we found a candidate
        if best_score == -1: best_score = 0
        score = best_score + 25 # +25 for invoice existing/count check
        feedback.insert(0, "New invoice document found")
    else:
        score = 0
        feedback.append("No suitable invoice found")
        
    # Cap score at 100
    score = min(100, score)
    
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": "; ".join(feedback)
    }