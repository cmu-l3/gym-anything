#!/usr/bin/env python3
"""
Verifier for Create Coupon Campaign task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_coupon_campaign(traj, env_info, task_info):
    """
    Verifies that the "Influencer Summer Campaign" promotion and its 5 coupons were created correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_coupons = metadata.get('coupons', {})
    
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
            
        score = 0
        feedback_parts = []
        
        # 1. Promotion Existence & Basic Config (45 points)
        if not result.get("promotion_found"):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Promotion 'Influencer Summer Campaign' not found."
            }
            
        # Name check (implicit in search, but good to confirm)
        score += 10
        feedback_parts.append("Promotion created")
        
        # Offer Type & Percentage (15 pts)
        offer_plugin = result.get("offer_plugin", "")
        offer_pct = result.get("offer_percentage", "0")
        try:
            pct_val = float(offer_pct)
        except:
            pct_val = 0.0
            
        if "percentage" in offer_plugin and abs(pct_val - 0.20) < 0.01:
            score += 15
            feedback_parts.append("Offer is 20% off")
        else:
            feedback_parts.append(f"Incorrect offer: Type={offer_plugin}, Value={offer_pct}")

        # Minimum Order Condition (15 pts)
        min_order = result.get("min_order_amount", "0")
        try:
            order_val = float(min_order)
        except:
            order_val = 0.0
            
        if abs(order_val - 200.0) < 0.1:
            score += 15
            feedback_parts.append("Min order $200 configured")
        else:
            feedback_parts.append(f"Incorrect min order: {min_order}")
            
        # Store & Settings (5 pts)
        if result.get("store_linked") and str(result.get("require_coupon")) == "1" and str(result.get("promotion_status")) == "1":
            score += 5
            feedback_parts.append("Store/Status/RequireCoupon settings correct")
        else:
            feedback_parts.append("Settings issue (Store/Status/RequireCoupon)")
            
        # 2. Coupon Verification (55 points total, ~11 pts each)
        # found_coupons contains list of dicts: {code, usage_limit, status, linked}
        found_coupons = result.get("found_coupons", [])
        
        # Normalize found coupons for lookup
        # Map uppercase code -> details
        found_map = {}
        for c in found_coupons:
            code = c.get("code", "").upper().strip()
            found_map[code] = c
            
        coupons_score = 0
        coupons_correct = 0
        
        for exp_code, exp_limit in expected_coupons.items():
            exp_code_upper = exp_code.upper()
            
            if exp_code_upper in found_map:
                c_data = found_map[exp_code_upper]
                
                # Check usage limit
                try:
                    actual_limit = int(c_data.get("usage_limit", -1))
                except:
                    actual_limit = -1
                
                # Check status
                status = str(c_data.get("status", "0"))
                
                if actual_limit == exp_limit and status == "1":
                    coupons_score += 11
                    coupons_correct += 1
                else:
                    # Partial credit for existing but wrong limit
                    coupons_score += 5
                    feedback_parts.append(f"Coupon {exp_code} incorrect limit ({actual_limit} vs {exp_limit})")
            else:
                feedback_parts.append(f"Coupon {exp_code} missing")
                
        score += coupons_score
        
        if coupons_correct == 5:
            feedback_parts.append("All 5 coupons correct")
            
        passed = score >= 70
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"System error during verification: {str(e)}"}