#!/usr/bin/env python3
"""
Verifier for create_loyalty_promotion task.

Scoring Breakdown (100 points):
- Promotion Created & Active (10 pts)
- Correct Name & Display Name (20 pts)
- Correct Offer (Fixed Amount $20) (30 pts)
- Correct Conditions (Min Order $100) (15 pts)
- Correct Limits (3 per customer, 500 total) (15 pts)
- Store Assigned & No Coupon (10 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_loyalty_promotion(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    
    # 2. Load Result
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found (export failed)"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    
    # 3. Verification Logic
    
    # Gating: Promotion must exist
    if not result.get('promotion_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No promotion matching 'Loyal Customer Reward' found."
        }
    
    # Criterion 1: Promotion Active (10 pts)
    status = str(result.get('status', '0'))
    if status == '1':
        score += 10
        feedback_parts.append("Promotion is active.")
    else:
        feedback_parts.append("Promotion exists but is disabled.")

    # Criterion 2: Naming (20 pts)
    name = result.get('name', '').strip()
    display_name = result.get('display_name', '').strip()
    
    if "loyal customer reward" in name.lower() and "$20" in name:
        score += 10
        feedback_parts.append("Internal name correct.")
    else:
        feedback_parts.append(f"Name mismatch: '{name}'")
        
    if "$20 off" in display_name.lower() and "100" in display_name:
        score += 10
        feedback_parts.append("Display name correct.")
    else:
        feedback_parts.append(f"Display name mismatch: '{display_name}'")

    # Criterion 3: Offer Configuration (30 pts)
    offer_plugin = result.get('offer_plugin', '')
    extracted_amount = result.get('extracted_offer_amount')
    
    # Check plugin type (fixed amount off)
    # Typically 'order_fixed_amount_off' or 'order_item_fixed_amount_off'
    if 'fixed_amount' in offer_plugin:
        score += 15
        feedback_parts.append("Correct offer type (Fixed Amount).")
        
        # Check Amount
        try:
            amt = float(extracted_amount) if extracted_amount else 0.0
            if abs(amt - 20.00) < 0.01:
                score += 15
                feedback_parts.append("Correct offer amount ($20.00).")
            else:
                feedback_parts.append(f"Wrong offer amount: ${amt}")
        except:
            feedback_parts.append("Could not verify offer amount.")
    else:
        feedback_parts.append(f"Wrong offer type: {offer_plugin}")

    # Criterion 4: Conditions (15 pts)
    cond_amount = result.get('extracted_condition_amount')
    if cond_amount:
        try:
            c_amt = float(cond_amount)
            if abs(c_amt - 100.00) < 0.01:
                score += 15
                feedback_parts.append("Correct condition (Min Order $100).")
            else:
                score += 5 # Partial for having condition but wrong amount
                feedback_parts.append(f"Condition exists but wrong amount: ${c_amt}")
        except:
            feedback_parts.append("Condition amount parse error.")
    else:
        feedback_parts.append("Minimum order condition not found.")

    # Criterion 5: Limits (15 pts)
    try:
        cust_limit = int(result.get('customer_usage_limit') or 0)
        total_limit = int(result.get('usage_limit') or 0)
        
        limits_ok = True
        if cust_limit == 3:
            score += 10
            feedback_parts.append("Customer usage limit correct (3).")
        else:
            limits_ok = False
            feedback_parts.append(f"Wrong customer limit: {cust_limit}")
            
        if total_limit == 500:
            score += 5
            feedback_parts.append("Total usage limit correct (500).")
        else:
            limits_ok = False
            feedback_parts.append(f"Wrong total limit: {total_limit}")
    except:
        feedback_parts.append("Error verifying limits.")

    # Criterion 6: Store & Coupon Setting (10 pts)
    store_linked = result.get('store_linked', False)
    require_coupon = str(result.get('require_coupon', '0'))
    
    if store_linked:
        score += 5
        feedback_parts.append("Store assigned.")
    else:
        feedback_parts.append("Store NOT assigned.")
        
    if require_coupon == '0':
        score += 5
        feedback_parts.append("Correctly set to Automatic (No coupon).")
    else:
        feedback_parts.append("Incorrectly requires a coupon.")

    # Final tally
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }