#!/usr/bin/env python3
"""
Verifier for Create European Store task.

Scoring (100 points):
- Store exists with correct name: 15 pts
- Currency is EUR: 15 pts
- Address is London, GB: 15 pts
- Store is active but not default: 10 pts
- Correct email: 5 pts
- Sony product assigned to new store: 15 pts
- Samsung product assigned to new store: 15 pts
- Logitech product assigned to new store: 10 pts

Penalties:
- Products removed from original store (destructive action): -10 pts per product
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_european_store(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/european_store_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    
    # Gate check
    if not result.get('store_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No store named 'Urban Electronics Europe' found"
        }

    # 1. Store Name (15 pts)
    store_name = result.get('store_name', '')
    if 'Urban Electronics Europe' in store_name:
        score += 15
        feedback_parts.append("Store name correct")
    else:
        feedback_parts.append(f"Store name match failed: '{store_name}'")

    # 2. Currency (15 pts)
    currency = result.get('store_currency', '')
    if currency == 'EUR':
        score += 15
        feedback_parts.append("Currency EUR correct")
    else:
        feedback_parts.append(f"Wrong currency: {currency}")

    # 3. Address (15 pts)
    country = result.get('address_country', '')
    locality = result.get('address_locality', '')
    if country == 'GB' and 'London' in locality:
        score += 15
        feedback_parts.append("Address (London, GB) correct")
    else:
        score += 5 if country == 'GB' else 0
        feedback_parts.append(f"Address check failed: {locality}, {country}")

    # 4. Active/Default status (10 pts)
    is_default = result.get('is_default')
    status = result.get('status')
    if str(status) == '1' and str(is_default) == '0':
        score += 10
        feedback_parts.append("Store active and not default")
    elif str(status) == '1':
        score += 5
        feedback_parts.append("Store active but wrongly set as default")
    else:
        feedback_parts.append("Store not active")

    # 5. Email (5 pts)
    email = result.get('store_mail', '')
    if 'europe@urbanelectronics.com' in email:
        score += 5
        feedback_parts.append("Email correct")
    else:
        feedback_parts.append("Email incorrect")

    # 6. Product Assignments (40 pts total)
    # Checks assignment to new store (must be 1) AND original store (must remain 1)
    
    def check_prod(name, new_val, old_val, points):
        prod_score = 0
        msg = []
        if int(new_val) > 0:
            prod_score += points
            msg.append(f"{name} assigned")
        else:
            msg.append(f"{name} NOT assigned")
            
        if int(old_val) == 0:
            prod_score -= 10 # Penalty for removing from original
            msg.append(f"(removed from US store!)")
            
        return max(0, prod_score), msg

    s_score, s_msg = check_prod("Sony", result.get('sony_assigned_new', 0), result.get('sony_assigned_old', 0), 15)
    score += s_score
    feedback_parts.extend(s_msg)

    sam_score, sam_msg = check_prod("Samsung", result.get('samsung_assigned_new', 0), result.get('samsung_assigned_old', 0), 15)
    score += sam_score
    feedback_parts.extend(sam_msg)

    l_score, l_msg = check_prod("Logitech", result.get('logi_assigned_new', 0), result.get('logi_assigned_old', 0), 10)
    score += l_score
    feedback_parts.extend(l_msg)

    # Final result
    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }