#!/usr/bin/env python3
"""
Verifier for Janitorial SKU Consolidation and Cleanup.

Verification Criteria:
1. Duplicates Archived (15 pts: 5 per pair) -> check `active == False`
2. Duplicates Zeroed Out (15 pts: 5 per pair) -> check `qty == 0`
3. Masters Quantities Correct (30 pts: 10 per pair) -> check `qty == expected_combined_stock`
4. Masters Remain Active (15 pts: 5 per pair) -> check `active == True`
5. Unrelated Untouched (25 pts) -> check `active == True` and stock unchanged for all 4.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_duplicate_sku_consolidation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/janitorial_cleanup_result.json')
    master_codes = metadata.get('master_codes', ["JAN-001", "JAN-002", "JAN-003"])
    duplicate_codes = metadata.get('duplicate_codes', ["JAN-001-DUP", "JAN-002-DUP", "JAN-003-DUP"])
    unrelated_codes = metadata.get('unrelated_codes', ["JAN-004", "JAN-005", "JAN-006", "JAN-007"])
    pairs = metadata.get('pairs', {
        "JAN-001-DUP": "JAN-001",
        "JAN-002-DUP": "JAN-002",
        "JAN-003-DUP": "JAN-003"
    })
    expected_combined_stock = metadata.get('expected_combined_stock', {
        "JAN-001": 25,
        "JAN-002": 15,
        "JAN-003": 32
    })
    initial_unrelated_stock = {
        "JAN-004": 50,
        "JAN-005": 30,
        "JAN-006": 25,
        "JAN-007": 5
    }

    score = 0
    feedback_parts = []

    # Copy export result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_file, temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    products = result.get('products', {})

    if not products:
        return {"passed": False, "score": 0, "feedback": "No product data found in export."}

    # CRITERIA 1 & 2: Duplicates Archived & Zeroed (30 pts total, 10 per duplicate)
    duplicates_handled = 0
    for dup_code in duplicate_codes:
        p_data = products.get(dup_code, {})
        if not p_data.get('found'):
            feedback_parts.append(f"FAIL: {dup_code} missing entirely.")
            continue
        
        is_archived = not p_data.get('active', True)
        is_zero = float(p_data.get('qty', -1)) == 0.0

        if is_archived:
            score += 5
        if is_zero:
            score += 5

        if is_archived and is_zero:
            duplicates_handled += 1
            feedback_parts.append(f"PASS: {dup_code} archived and zeroed (+10).")
        else:
            feedback_parts.append(f"FAIL: {dup_code} archived={is_archived}, qty={p_data.get('qty')}.")

    # CRITERIA 3 & 4: Masters Correct Qty & Active (45 pts total, 15 per master)
    masters_handled = 0
    for dup_code, master_code in pairs.items():
        p_data = products.get(master_code, {})
        if not p_data.get('found'):
            feedback_parts.append(f"FAIL: {master_code} missing entirely.")
            continue
        
        is_active = p_data.get('active', False)
        actual_qty = float(p_data.get('qty', 0))
        expected_qty = float(expected_combined_stock.get(master_code, 0))

        if is_active:
            score += 5
        if abs(actual_qty - expected_qty) < 0.1:
            score += 10
            masters_handled += 1
            if is_active:
                feedback_parts.append(f"PASS: {master_code} active with combined stock {actual_qty} (+15).")
        else:
            feedback_parts.append(f"FAIL: {master_code} stock is {actual_qty}, expected {expected_qty}.")

    # CRITERION 5: Unrelated Products Untouched (25 pts anti-gaming)
    unrelated_untouched = True
    for un_code in unrelated_codes:
        p_data = products.get(un_code, {})
        if not p_data.get('found'):
            unrelated_untouched = False
            feedback_parts.append(f"FAIL: Unrelated product {un_code} missing.")
            continue
        
        is_active = p_data.get('active', False)
        actual_qty = float(p_data.get('qty', 0))
        expected_qty = float(initial_unrelated_stock.get(un_code, 0))

        if not is_active or abs(actual_qty - expected_qty) > 0.1:
            unrelated_untouched = False
            feedback_parts.append(f"FAIL: Unrelated {un_code} was modified (active={is_active}, qty={actual_qty}).")

    if unrelated_untouched:
        score += 25
        feedback_parts.append("PASS: All unrelated products remained untouched (+25).")
    else:
        # Severe penalty for touching unrelated products
        score = min(score, 55)
        feedback_parts.append("FAIL: Unrelated products modified. Score capped at 55.")

    # Determine final pass/fail
    passed = score >= 80 and unrelated_untouched

    return {
        "passed": bool(passed),
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }