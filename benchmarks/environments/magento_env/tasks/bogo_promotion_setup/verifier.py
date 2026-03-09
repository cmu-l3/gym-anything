#!/usr/bin/env python3
"""Verifier for BOGO Promotion Setup task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bogo_promotion(traj, env_info, task_info):
    """
    Verify the 'Clothing BOGO' rule configuration.
    
    Criteria:
    1. Rule 'Clothing BOGO' exists and is active (20 pts)
    2. Action is 'buy_x_get_y' (20 pts)
    3. Discount Amount is 1 (15 pts)
    4. Discount Step is 3 (Buy 2 Get 1 = 3 total) (25 pts)
    5. Condition targets Clothing category (15 pts)
    6. No Coupon (Auto-apply) (5 pts)
    
    Pass threshold: 60 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/bogo_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
            
        score = 0
        feedback_parts = []
        
        rule_found = result.get('rule_found', False)
        rule = result.get('rule', {})
        
        # Criterion 1: Rule Exists (Gate)
        if not rule_found:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Rule 'Clothing BOGO' not found in database."
            }
        
        # Check Active Status
        is_active = str(rule.get('is_active', '0')).strip()
        if is_active == '1':
            score += 20
            feedback_parts.append("Rule exists and is active (20 pts)")
        else:
            score += 10
            feedback_parts.append("Rule exists but is INACTIVE (10 pts)")
            
        # Criterion 2: Action Type
        action = rule.get('simple_action', '')
        if action == 'buy_x_get_y':
            score += 20
            feedback_parts.append("Correct action type: Buy X get Y free (20 pts)")
        else:
            feedback_parts.append(f"Incorrect action type: {action} (Expected: buy_x_get_y)")
            
        # Criterion 3: Discount Amount (Should be 1 for 'Get 1 Free')
        try:
            amount = float(rule.get('discount_amount', 0))
            if abs(amount - 1.0) < 0.01:
                score += 15
                feedback_parts.append("Correct discount amount: 1 (15 pts)")
            else:
                feedback_parts.append(f"Incorrect discount amount: {amount} (Expected: 1)")
        except:
            feedback_parts.append("Invalid discount amount format")

        # Criterion 4: Discount Step (Should be 3 for 'Buy 2 Get 1')
        try:
            step = int(rule.get('discount_step', 0))
            if step == 3:
                score += 25
                feedback_parts.append("Correct discount step: 3 (25 pts)")
            else:
                feedback_parts.append(f"Incorrect discount step: {step} (Expected: 3 for Buy 2 + 1)")
        except:
             feedback_parts.append("Invalid discount step format")
             
        # Criterion 5: Category Condition
        cat_met = rule.get('category_condition_met', False)
        if cat_met:
            score += 15
            feedback_parts.append("Conditions correctly target Clothing category (15 pts)")
        else:
            feedback_parts.append("Conditions do NOT appear to target the Clothing category")
            
        # Criterion 6: No Coupon (Auto-apply)
        # coupon_type: 1=No Coupon, 2=Specific, 3=Auto
        coupon_type = str(rule.get('coupon_type', ''))
        if coupon_type == '1':
            score += 5
            feedback_parts.append("Correct coupon setting: No Coupon (5 pts)")
        else:
            feedback_parts.append(f"Incorrect coupon setting (Type: {coupon_type})")
            
        passed = score >= 60
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}