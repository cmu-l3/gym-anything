#!/usr/bin/env python3
"""
Verifier for inventory_uom_procurement_flow task.

Criteria:
1. UoM Feature Enabled (10 pts)
2. UoM "Case of 24" configured correctly (Ratio 24) (25 pts)
3. Product configured (Purchase UoM = Case, Sales UoM = Unit) (25 pts)
4. Purchase Order created for 5 Cases (15 pts)
5. Final Stock is 120 Units (25 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_inventory_uom_procurement_flow(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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
    feedback = []
    
    # 1. Feature Enabled (10 pts)
    if result.get('feature_enabled'):
        score += 10
        feedback.append("Feature 'Units of Measure' enabled.")
    else:
        feedback.append("Feature 'Units of Measure' NOT enabled.")

    # 2. UoM Configuration (25 pts)
    uom_exists = result.get('uom_exists')
    ratio = result.get('uom_ratio', 0)
    uom_type = result.get('uom_type', '')
    
    if uom_exists:
        # Check ratio. Odoo stores 'bigger' ratio in factor_inv for some versions, or inverse.
        # Usually for "Bigger than reference", factor_inv = 24.
        # We accept 24.0.
        if abs(ratio - 24.0) < 0.1 and uom_type == 'bigger':
            score += 25
            feedback.append("UoM 'Case of 24' configured correctly (24x).")
        else:
            score += 10 # Partial credit for creating it
            feedback.append(f"UoM exists but ratio/type incorrect (Ratio: {ratio}, Type: {uom_type}). Expected 24.0/bigger.")
    else:
        feedback.append("UoM 'Case of 24' not found.")

    # 3. Product Configuration (25 pts)
    if result.get('product_exists'):
        p_uom = result.get('product_uom_name', '')
        po_uom = result.get('product_po_uom_name', '')
        
        pts_prod = 0
        if 'Unit' in p_uom:
            pts_prod += 10
        if 'Case' in po_uom:
            pts_prod += 15
        
        score += pts_prod
        if pts_prod == 25:
            feedback.append("Product UoMs configured correctly.")
        else:
            feedback.append(f"Product UoM mismatch. Stock: {p_uom}, Purchase: {po_uom}.")
    else:
        feedback.append("Product 'Glacier Spring Water 500ml' not found.")

    # 4. Purchase Order (15 pts)
    po_qty = result.get('po_line_qty', 0)
    po_uom = result.get('po_line_uom', '')
    
    if po_qty == 5 and 'Case' in str(po_uom):
        score += 15
        feedback.append("Purchase Order for 5 Cases found.")
    elif po_qty > 0:
        score += 5
        feedback.append(f"Purchase Order found but quantity/UoM incorrect ({po_qty} {po_uom}).")
    else:
        feedback.append("No valid Purchase Order found.")

    # 5. Stock Level (25 pts)
    stock_qty = result.get('stock_qty', 0)
    
    if abs(stock_qty - 120.0) < 0.1:
        # Anti-gaming check: did it come from a vendor?
        if result.get('vendor_moves_count', 0) > 0:
            score += 25
            feedback.append("Final stock quantity is correct (120 Units) and came from vendor.")
        else:
            score += 10
            feedback.append("Final stock quantity is correct, but no vendor receipt found (Anti-gaming penalty).")
    else:
        feedback.append(f"Final stock quantity incorrect. Expected 120, got {stock_qty}.")

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " ".join(feedback)
    }