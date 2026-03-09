#!/usr/bin/env python3
"""Verifier for Offline Payment Configuration task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_offline_payment_config(traj, env_info, task_info):
    """
    Verify payment method configuration.

    Criteria:
    1. Bank Transfer enabled (10 pts)
    2. Bank Transfer title correct (10 pts)
    3. Bank Instructions contain correct Routing & Account numbers (20 pts)
    4. Bank Sort Order is 10 (10 pts)
    5. Check/Money Order enabled (10 pts)
    6. Check Title correct (10 pts)
    7. Check Payable To correct (10 pts)
    8. Check Mailing Address contains correct street (10 pts)
    9. Check Sort Order is 20 (10 pts)

    Pass threshold: 70 pts
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    
    # Expected values
    exp_bank_title = metadata.get('bank_title', 'Wire Transfer / ACH')
    exp_bank_routing = metadata.get('bank_routing', '021000021')
    exp_bank_account = metadata.get('bank_account', '9876543210')
    exp_bank_sort = metadata.get('bank_sort', '10')
    
    exp_check_title = metadata.get('check_title', 'Corporate Check')
    exp_check_payable = metadata.get('check_payable', 'TechCorp Solutions')
    exp_check_addr_part = metadata.get('check_address_part', '123 Tech Blvd')
    exp_check_sort = metadata.get('check_sort', '20')

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/payment_config_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    score = 0
    feedback_parts = []
    
    bank = result.get('bank_transfer', {})
    check = result.get('check_money_order', {})

    # --- Verify Bank Transfer ---
    
    # 1. Enabled (10 pts)
    if str(bank.get('active', '0')).strip() == '1':
        score += 10
        feedback_parts.append("Bank Transfer enabled")
    else:
        feedback_parts.append("Bank Transfer NOT enabled")

    # 2. Title (10 pts)
    if bank.get('title', '').strip().lower() == exp_bank_title.lower():
        score += 10
        feedback_parts.append("Bank Title correct")
    else:
        feedback_parts.append(f"Bank Title incorrect (expected '{exp_bank_title}')")

    # 3. Instructions (20 pts)
    instr = bank.get('instructions_raw', '')
    if exp_bank_routing in instr and exp_bank_account in instr:
        score += 20
        feedback_parts.append("Bank Instructions correct")
    else:
        feedback_parts.append("Bank Instructions missing account/routing details")

    # 4. Sort Order (10 pts)
    if str(bank.get('sort_order', '')).strip() == exp_bank_sort:
        score += 10
        feedback_parts.append("Bank Sort Order correct")
    else:
        feedback_parts.append(f"Bank Sort Order incorrect (expected {exp_bank_sort})")

    # --- Verify Check / Money Order ---

    # 5. Enabled (10 pts)
    if str(check.get('active', '0')).strip() == '1':
        score += 10
        feedback_parts.append("Check enabled")
    else:
        feedback_parts.append("Check NOT enabled")

    # 6. Title (10 pts)
    if check.get('title', '').strip().lower() == exp_check_title.lower():
        score += 10
        feedback_parts.append("Check Title correct")
    else:
        feedback_parts.append(f"Check Title incorrect (expected '{exp_check_title}')")

    # 7. Payable To (10 pts)
    if check.get('payable_to', '').strip().lower() == exp_check_payable.lower():
        score += 10
        feedback_parts.append("Check Payable To correct")
    else:
        feedback_parts.append(f"Check Payable incorrect (expected '{exp_check_payable}')")

    # 8. Address (10 pts)
    if exp_check_addr_part.lower() in check.get('mailing_address_raw', '').lower():
        score += 10
        feedback_parts.append("Check Address correct")
    else:
        feedback_parts.append("Check Address missing street info")

    # 9. Sort Order (10 pts)
    if str(check.get('sort_order', '')).strip() == exp_check_sort:
        score += 10
        feedback_parts.append("Check Sort Order correct")
    else:
        feedback_parts.append(f"Check Sort Order incorrect (expected {exp_check_sort})")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }