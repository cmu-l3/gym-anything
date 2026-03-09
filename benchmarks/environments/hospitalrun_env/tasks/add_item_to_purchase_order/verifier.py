#!/usr/bin/env python3
"""
Verifier for add_item_to_purchase_order task.

Checks:
1. Purchase Order document exists and was modified (rev changed).
2. Item count is exactly 2.
3. Original item (Surgical Gowns) is preserved.
4. New item (N95 Respirator) is added with correct Quantity and Price.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_item_to_purchase_order(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata expectations
    metadata = task_info.get('metadata', {})
    expected_new_name = metadata.get('new_item_name', 'N95 Respirator')
    expected_new_qty = metadata.get('new_item_qty', 50)
    expected_new_price = metadata.get('new_item_price', 1.50)
    expected_old_name = metadata.get('existing_item_name', 'Surgical Gowns')

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    po_doc = result.get('po_document', {})
    initial_rev = result.get('initial_rev', '')
    current_rev = po_doc.get('_rev', '')
    
    score = 0
    feedback_parts = []
    
    # Criterion 1: Document Modified (20 pts)
    # Anti-gaming: Ensure the agent actually saved the record
    if not current_rev or current_rev == initial_rev:
        feedback_parts.append("Purchase Order was NOT modified (revision unchanged).")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": " | ".join(feedback_parts)
        }
    else:
        score += 20
        feedback_parts.append("Purchase Order modified successfully")

    # Criterion 2: Item Count (20 pts)
    items = po_doc.get('items', [])
    if len(items) == 2:
        score += 20
        feedback_parts.append("Correct number of items (2)")
    else:
        feedback_parts.append(f"Incorrect item count: expected 2, got {len(items)}")
        # If they deleted the old one and added the new one, they get partial credit later, but fail this

    # Criterion 3: Verify New Item (40 pts)
    new_item_found = False
    new_item_correct = False
    
    for item in items:
        # Check name partial match
        name = item.get('name', '')
        if expected_new_name.lower() in name.lower() or 'n95' in name.lower():
            new_item_found = True
            
            # Check details
            qty = item.get('quantity', 0)
            price = item.get('unitPrice', 0)
            
            qty_ok = False
            try:
                if int(qty) == int(expected_new_qty):
                    qty_ok = True
            except: pass
            
            price_ok = False
            try:
                if abs(float(price) - float(expected_new_price)) < 0.01:
                    price_ok = True
            except: pass
            
            if qty_ok and price_ok:
                score += 40
                new_item_correct = True
                feedback_parts.append(f"New item '{name}' added with correct Qty ({qty}) and Price ({price})")
            else:
                score += 10 # Partial credit for finding item but wrong values
                feedback_parts.append(f"New item '{name}' found but values incorrect (Qty: {qty}, Price: {price})")
            break
            
    if not new_item_found:
        feedback_parts.append(f"New item '{expected_new_name}' NOT found in order")

    # Criterion 4: Verify Old Item Preserved (20 pts)
    old_item_preserved = False
    for item in items:
        name = item.get('name', '')
        # Check for gowns
        if expected_old_name.lower() in name.lower() or 'gowns' in name.lower():
            old_item_preserved = True
            score += 20
            feedback_parts.append("Original item preserved")
            break
            
    if not old_item_preserved:
        feedback_parts.append("Original item (Surgical Gowns) was deleted or overwritten")

    # Final Check
    passed = (score >= 80) and new_item_correct and old_item_preserved

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }