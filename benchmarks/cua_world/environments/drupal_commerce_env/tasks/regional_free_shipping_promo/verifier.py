#!/usr/bin/env python3
"""
Verifier for Regional Free Shipping Promotion task.

Verifies:
1. Promotion exists and is active.
2. Offer is 100% off shipping.
3. Condition: Order total >= $100.
4. Condition: Address is California, US.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_regional_free_shipping_promo(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Promotion Created (10 pts)
    if result.get('promotion_found'):
        score += 5
        feedback_parts.append("Promotion found")
        
        if result.get('promotion_status') == "1":
            score += 5
            feedback_parts.append("Promotion is active")
        else:
            feedback_parts.append("Promotion is disabled (-5 pts)")
            
        # Anti-gaming: Check timestamp
        if result.get('is_newly_created'):
            feedback_parts.append("Confirmed created during task")
        else:
            feedback_parts.append("Warning: Promotion existed before task start")
    else:
        return {"passed": False, "score": 0, "feedback": "No promotion named 'California Pilot' found"}

    # 2. Offer Configuration (40 pts total)
    # Offer type (20 pts)
    offer_id = result.get('offer_plugin_id', '')
    if 'shipping' in offer_id and 'percentage' in offer_id:
        score += 20
        feedback_parts.append("Correct offer type (Shipping Percentage)")
    elif 'percentage' in offer_id:
        # Partial credit if they picked product percentage instead of shipping
        score += 5
        feedback_parts.append("Wrong offer type: selected Product Percentage instead of Shipping Percentage")
    else:
        feedback_parts.append(f"Incorrect offer type: {offer_id}")

    # Offer value (20 pts)
    try:
        pct = float(result.get('offer_percentage', 0))
        # 1.0 is 100%, 100 might also be stored depending on version/input
        if abs(pct - 1.0) < 0.01 or abs(pct - 100.0) < 0.01:
            score += 20
            feedback_parts.append("Correct discount amount (100%)")
        else:
            feedback_parts.append(f"Incorrect discount amount: {pct}")
    except (ValueError, TypeError):
        feedback_parts.append("Could not verify discount amount")

    # 3. Conditions (50 pts total)
    # Price Condition (25 pts)
    if result.get('has_price_condition'):
        try:
            amount = float(result.get('price_condition_amount', 0))
            if abs(amount - 100.0) < 0.01:
                score += 25
                feedback_parts.append("Correct minimum order condition ($100)")
            else:
                score += 10
                feedback_parts.append(f"Minimum order condition present but wrong amount: ${amount}")
        except:
            score += 10
            feedback_parts.append("Minimum order condition present but amount unverified")
    else:
        feedback_parts.append("Missing minimum order condition")

    # Address Condition (25 pts)
    if result.get('has_address_condition'):
        country = result.get('address_country', '')
        zone = result.get('address_zone', '')
        
        if country == "US" and zone == "CA":
            score += 25
            feedback_parts.append("Correct address condition (CA, US)")
        elif country == "US":
            score += 10
            feedback_parts.append("Address condition targets US, but California zone missing")
        else:
            score += 5
            feedback_parts.append("Address condition present but incorrect target")
    else:
        feedback_parts.append("Missing address/zone condition")

    # Final Result
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }