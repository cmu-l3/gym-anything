#!/usr/bin/env python3
"""
Verifier for create_purchase_order task in Vtiger CRM.

VERIFICATION CRITERIA:
1. Anti-gaming: Ensure PO was newly created (current_count > initial_count)
2. PO Record Exists (15 pts)
3. Vendor correctly associated (10 pts)
4. PO Number correct (5 pts)
5. Line Items correct:
   - 3 correct products added (15 pts)
   - 3 correct quantities entered (15 pts)
   - 3 correct list prices entered (15 pts)
6. VLM Trajectory Verification: Confirms visual UI interaction (25 pts)

Maximum Score: 100 points
Pass Threshold: 60 points + Anti-gaming passed
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are verifying if an AI agent successfully completed a task in Vtiger CRM.
Task: Create a Purchase Order for vendor 'SunBelt Outdoor Supply' with specific landscaping line items.

Review the sequence of trajectory screenshots from the agent's screen.
Did the agent actively use the Vtiger CRM user interface to fill out the Purchase Order form?
Look specifically for:
- Typing 'Spring 2025 Landscaping Materials' into a subject field.
- Opening the Vendor selection popup and selecting 'SunBelt Outdoor Supply'.
- Using the 'Add Product' or 'Add Service' row functionality.
- Entering line items like 'Commercial Fertilizer', 'Bermuda Grass Seed', or 'Drip Irrigation Kit'.

Respond with a JSON object:
{
    "ui_interaction_confirmed": true/false,
    "reasoning": "brief explanation"
}
"""

def verify_create_purchase_order(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Extract metadata expected values
    metadata = task_info.get('metadata', {})
    expected_vendor = metadata.get('expected_vendor', 'SunBelt Outdoor Supply')
    expected_po_number = metadata.get('expected_po_number', 'PO-2025-0042')
    expected_items = metadata.get('expected_items', [])

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    initial_count = result.get('initial_po_count', 0)
    current_count = result.get('current_po_count', 0)
    po_found = result.get('po_found', False)
    
    # 1. Anti-gaming check
    if current_count <= initial_count and not po_found:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Fail: No new Purchase Orders created (initial={initial_count}, current={current_count})"
        }
        
    if not po_found:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Fail: Purchase Order with subject 'Spring 2025 Landscaping Materials' not found"
        }

    # 2. PO Record Exists
    score += 15
    feedback_parts.append("PO Record exists (+15)")
    
    # 3. Vendor Association
    vendor_name = result.get('vendor_name', '')
    if expected_vendor.lower() in vendor_name.lower():
        score += 10
        feedback_parts.append("Vendor correct (+10)")
    else:
        feedback_parts.append(f"Vendor mismatch: expected '{expected_vendor}', got '{vendor_name}'")
        
    # 4. PO Number
    po_number = result.get('po_number', '')
    if po_number.strip() == expected_po_number:
        score += 5
        feedback_parts.append("PO Number correct (+5)")
    else:
        feedback_parts.append(f"PO Number mismatch: expected '{expected_po_number}', got '{po_number}'")
        
    # 5. Line Items verification
    actual_items = result.get('line_items', [])
    actual_item_dicts = {item.get('productname', '').lower().strip(): item for item in actual_items}
    
    items_matched = 0
    qty_matched = 0
    price_matched = 0
    
    for expected in expected_items:
        exp_name = expected['name'].lower().strip()
        exp_qty = float(expected['qty'])
        exp_price = float(expected['price'])
        
        if exp_name in actual_item_dicts:
            items_matched += 1
            actual = actual_item_dicts[exp_name]
            
            # Check quantity
            actual_qty = float(actual.get('quantity', 0))
            if abs(actual_qty - exp_qty) < 0.01:
                qty_matched += 1
                
            # Check price
            actual_price = float(actual.get('listprice', 0))
            if abs(actual_price - exp_price) < 0.05:
                price_matched += 1
    
    # Scoring line items (up to 45 pts total)
    prod_score = items_matched * 5
    qty_score = qty_matched * 5
    price_score = price_matched * 5
    
    score += (prod_score + qty_score + price_score)
    feedback_parts.append(f"Products: {items_matched}/3 (+{prod_score})")
    feedback_parts.append(f"Quantities: {qty_matched}/3 (+{qty_score})")
    feedback_parts.append(f"Prices: {price_matched}/3 (+{price_score})")

    # 6. VLM Trajectory Verification
    vlm_score = 0
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=4)
            
            if frames:
                vlm_result = query_vlm(
                    images=frames,
                    prompt=VERIFICATION_PROMPT
                )
                
                if vlm_result and vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    if parsed.get('ui_interaction_confirmed', False):
                        vlm_score = 25
                        score += vlm_score
                        feedback_parts.append("VLM: UI interaction confirmed (+25)")
                    else:
                        feedback_parts.append(f"VLM: UI interaction not confirmed. Reason: {parsed.get('reasoning', '')}")
                else:
                    feedback_parts.append("VLM query failed")
            else:
                feedback_parts.append("VLM: No trajectory frames available")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            feedback_parts.append("VLM verification errored")
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }