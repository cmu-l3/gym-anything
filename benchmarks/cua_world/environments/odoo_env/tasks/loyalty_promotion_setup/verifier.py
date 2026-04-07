#!/usr/bin/env python3
"""
Verifier for loyalty_promotion_setup task.
Checks if the Odoo Loyalty Program was correctly configured and applied.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_loyalty_promotion_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/loyalty_promotion_setup_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Check Program Existence
    if result.get('program_found'):
        score += 10
        feedback.append("Loyalty Program created.")
        
        prog_details = result.get('program_correct', {})
        if prog_details.get('name_match'):
            score += 10
            feedback.append("Program name is correct.")
        else:
            feedback.append("Program name incorrect.")
            
    else:
        feedback.append("Loyalty Program NOT found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Check Rules
    rules = result.get('rules_correct', {})
    code_match = rules.get('code') == 'SCREEN15' or result.get('setup', {}).get('target_code') in str(rules)
    # Note: Sometimes code is on program trigger in newer Odoo versions, checking broadly
    
    if code_match:
        score += 10
        feedback.append("Promo code configured.")
    else:
        feedback.append("Promo code configuration issue.")

    if rules.get('min_qty') == 5:
        score += 15
        feedback.append("Minimum quantity rule correct (5).")
    else:
        feedback.append(f"Minimum quantity incorrect: found {rules.get('min_qty')}.")

    if rules.get('correct_product'):
        score += 15
        feedback.append("Product restriction configured correctly.")
    else:
        feedback.append("Product restriction missing or incorrect.")

    # Check Rewards
    rewards = result.get('rewards_correct', {})
    if rewards.get('discount') == 15 and (rewards.get('mode') == 'percent' or rewards.get('mode') == 'percentage'):
        score += 15
        feedback.append("Reward is 15% discount.")
    else:
        feedback.append(f"Reward incorrect: found {rewards.get('discount')}% {rewards.get('mode')}.")

    # Check Execution (Order)
    if result.get('order_found'):
        order_details = result.get('order_correct', {})
        if order_details.get('target_product_found'):
            score += 10
            feedback.append("Sales order created with target product.")
        else:
            feedback.append("Sales order missing target product.")
            
        if order_details.get('discount_applied'):
            score += 15
            feedback.append("Discount successfully applied to order.")
        else:
            feedback.append("Discount NOT applied to order.")
    else:
        feedback.append("No sales order found for verification.")

    passed = score >= 70 and result.get('order_correct', {}).get('discount_applied')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result
    }