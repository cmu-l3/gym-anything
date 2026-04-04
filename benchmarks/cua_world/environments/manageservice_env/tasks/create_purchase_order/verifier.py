#!/usr/bin/env python3
"""
Verifier for create_purchase_order task.

Checks:
1. PO existence (created after task start)
2. PO Name
3. Vendor Name
4. Total Amount
5. Line Items (Quantity, Price, Name match)
6. Due Date
"""

import json
import logging
import os
import tempfile
import sys
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_purchase_order(traj, env_info, task_info):
    """
    Verify the creation of a specific Purchase Order in ServiceDesk Plus.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    expected_po_name = metadata.get('expected_po_name', "")
    expected_vendor = metadata.get('expected_vendor', "")
    expected_total = metadata.get('expected_total', 0.0)
    expected_due_date = metadata.get('expected_due_date', "")
    expected_items = metadata.get('line_items', [])
    tolerance_total = metadata.get('tolerance_total', 1000.0)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Check if PO was found (created after task start) (15 pts)
    if not result.get('po_found', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No new Purchase Order found created during the task session."
        }
    
    score += 15
    feedback_parts.append("New Purchase Order created")
    
    # 2. Check PO Name (10 pts)
    actual_name = result.get('po_name', "")
    if expected_po_name.lower() in str(actual_name).lower():
        score += 10
        feedback_parts.append(f"PO Name correct ('{actual_name}')")
    else:
        feedback_parts.append(f"PO Name mismatch: expected '{expected_po_name}', got '{actual_name}'")

    # 3. Check Vendor (15 pts)
    actual_vendor = result.get('vendor', "")
    if expected_vendor.lower() in str(actual_vendor).lower():
        score += 15
        feedback_parts.append(f"Vendor correct ('{actual_vendor}')")
    else:
        feedback_parts.append(f"Vendor mismatch: expected '{expected_vendor}', got '{actual_vendor}'")

    # 4. Check Due Date (10 pts)
    actual_due = result.get('due_date', "")
    # Simple string match YYYY-MM-DD
    if actual_due and expected_due_date in actual_due:
        score += 10
        feedback_parts.append(f"Due Date correct ({actual_due})")
    else:
        feedback_parts.append(f"Due Date incorrect: expected {expected_due_date}, got {actual_due}")

    # 5. Check Total (10 pts)
    actual_total = result.get('total', 0.0)
    if abs(actual_total - expected_total) <= tolerance_total:
        score += 10
        feedback_parts.append(f"Total Amount correct (${actual_total})")
    else:
        feedback_parts.append(f"Total Amount incorrect: expected ~${expected_total}, got ${actual_total}")

    # 6. Check Line Items (30 pts total)
    # Strategy: Look for items matching description, qty, and price
    actual_items = result.get('items', [])
    items_matched = 0
    
    for expected in expected_items:
        found = False
        for actual in actual_items:
            name_match = expected['name_part'].lower() in str(actual.get('name', '')).lower()
            qty_match = abs(float(actual.get('quantity', 0)) - expected['qty']) < 0.1
            price_match = abs(float(actual.get('price', 0)) - expected['price']) < 1.0
            
            if name_match and qty_match and price_match:
                found = True
                break
        
        if found:
            items_matched += 1
            feedback_parts.append(f"Item '{expected['name_part']}' found")
        else:
            feedback_parts.append(f"Item '{expected['name_part']}' NOT found")

    # Scoring items: 15 pts per item (2 items total = 30 pts)
    score += (items_matched * 15)

    # 7. VLM Verification (10 pts)
    # Verify the agent actually used the UI form
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Check if these screenshots show the user interacting with a Purchase Order form in ServiceDesk Plus.
    Look for:
    1. 'New Purchase Order' screen or list.
    2. Entering details like 'Cisco Systems' or prices.
    3. The final list of purchase orders.
    Did the user perform the task in the UI?
    """
    
    vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
    if vlm_result.get('success', False) and 'yes' in vlm_result.get('parsed', {}).get('answer', '').lower():
        score += 10
        feedback_parts.append("UI interaction verified")
    elif "yes" in str(vlm_result.get('response', '')).lower():
         score += 10
         feedback_parts.append("UI interaction verified")
    else:
        feedback_parts.append("VLM could not verify UI interaction")

    passed = score >= 60 and result.get('po_found', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }