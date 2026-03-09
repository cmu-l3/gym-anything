#!/usr/bin/env python3
"""
Verifier for configure_cash_rounding task.

Criteria:
1. Registry: Rounding Interval must be 0.05 (30 pts)
2. Registry: Rounding Type must be set (10 pts)
3. VLM: Final screen shows a transaction total of $1.05 (indicating rounding happened) (40 pts)
4. VLM: Final screen shows 'Cash' payment (10 pts)
5. App running (10 pts)

Pass threshold: 70 points (Must have config correct AND VLM evidence of rounding)
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_cash_rounding(traj, env_info, task_info):
    """
    Verify Cash Rounding configuration and test sale.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Parse Programmatic Results (Registry)
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Windows\\Temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Check App Running
    if result.get('app_running', False):
        score += 10
        feedback_parts.append("Copper POS is running.")
    else:
        feedback_parts.append("Copper POS was NOT running.")

    # Check Registry Config
    config = result.get('config', {})
    r_interval = str(config.get('rounding_interval', ''))
    r_type = str(config.get('rounding_type', ''))
    
    # Allow 0.05 or 5 or 5 cents depending on how it's stored, usually string "0.05" or float
    if "0.05" in r_interval or "5" in r_interval:
        score += 30
        feedback_parts.append(f"Rounding interval correctly set to {r_interval}.")
    else:
        feedback_parts.append(f"Rounding interval incorrect: {r_interval} (Expected 0.05).")

    if r_type and r_type != "Not Set":
        score += 10
        feedback_parts.append("Rounding rule configured.")
    else:
        feedback_parts.append("Rounding rule NOT configured.")

    # 2. VLM Verification (Evidence of successful test)
    # We look for the receipt or transaction summary showing the rounding
    final_img = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze this Point of Sale screen. 
    1. Look for a 'Total' or 'Amount Due'. 
    2. Look for evidence of a transaction with 'Washer' (or similar item) and 'Cash'.
    3. Specifically check if the total amount is '$1.05' or if there is a line item saying 'Rounding: 0.02'.
    
    The user was supposed to buy items totaling $1.03 and pay with cash, causing a round-up to $1.05.
    
    Return JSON:
    {
        "total_visible": true/false,
        "total_value": "string value of total",
        "rounding_visible": true/false,
        "cash_payment_visible": true/false,
        "items_visible": ["list of visible item names"]
    }
    """
    
    vlm_result = query_vlm(images=[final_img], prompt=vlm_prompt)
    vlm_data = vlm_result.get('parsed', {}) if vlm_result.get('success') else {}
    
    total_val = vlm_data.get('total_value', '')
    
    # Score VLM
    if "1.05" in total_val:
        score += 40
        feedback_parts.append("VLM verified Total is $1.05 (Rounding applied).")
    elif vlm_data.get('rounding_visible'):
        score += 40
        feedback_parts.append("VLM verified Rounding line item is visible.")
    elif "1.03" in total_val:
        feedback_parts.append("VLM saw Total $1.03 - Rounding NOT applied.")
    else:
        feedback_parts.append(f"VLM could not confirm specific total (Saw: '{total_val}').")

    if vlm_data.get('cash_payment_visible'):
        score += 10
        feedback_parts.append("Cash payment method verified.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }