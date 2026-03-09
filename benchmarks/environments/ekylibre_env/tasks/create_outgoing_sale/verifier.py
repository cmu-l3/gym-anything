#!/usr/bin/env python3
"""
Verifier for create_outgoing_sale task in Ekylibre.

Verification Criteria:
1. New sale record exists (created after task start) - 25 pts
2. Sale is linked to a valid client entity - 15 pts
3. Sale has at least one line item - 20 pts
4. Line item quantity matches 25 (±0.5) - 20 pts
5. Line item unit price matches 210.00 (±1.0) - 20 pts

Total: 100 pts
Pass Threshold: 60 pts
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_outgoing_sale(traj, env_info, task_info):
    """
    Verify that a new outgoing sale was created with specific details.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve expectations
    metadata = task_info.get('metadata', {})
    expected_qty = metadata.get('expected_quantity', 25)
    expected_price = metadata.get('expected_price', 210.00)
    qty_tol = metadata.get('quantity_tolerance', 0.5)
    price_tol = metadata.get('price_tolerance', 1.0)

    # 1. Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Parse Data
    initial_count = int(result.get('initial_sales_count', 0))
    current_count = int(result.get('current_sales_count', 0))
    latest_sale = result.get('latest_sale', {})
    sale_items = result.get('sale_items', [])
    if sale_items is None: sale_items = []
    client_name = result.get('client_name', "")
    task_start = result.get('task_start', 0)
    
    # CRITERION 1: New sale record exists (25 pts)
    new_sale_exists = False
    
    if current_count > initial_count:
        # Check if the latest sale was actually created during the task
        # PostgreSQL extract epoch returns seconds
        sale_ts = latest_sale.get('created_ts', 0)
        
        # Allow a small buffer (sometimes clocks drift slightly between container/host)
        if sale_ts >= (task_start - 10):
            new_sale_exists = True
            score += 25
            feedback_parts.append("New sale record created.")
        else:
            feedback_parts.append("Sales count increased, but latest sale timestamp is too old (pre-existing?).")
    else:
        feedback_parts.append("No new sale record found in database.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # CRITERION 2: Valid Client (15 pts)
    if new_sale_exists:
        client_id = latest_sale.get('client_id')
        if client_id and client_name:
            score += 15
            feedback_parts.append(f"Client assigned: {client_name}.")
        else:
            feedback_parts.append("Sale created but no client assigned.")

    # CRITERION 3: Line items exist (20 pts)
    has_items = len(sale_items) > 0
    if has_items:
        score += 20
        feedback_parts.append(f"Sale has {len(sale_items)} line item(s).")
    else:
        feedback_parts.append("Sale has no line items.")

    # CRITERION 4 & 5: Check values (20 + 20 pts)
    if has_items:
        qty_match = False
        price_match = False
        
        for item in sale_items:
            # Check Quantity
            q = float(item.get('quantity', 0))
            if abs(q - expected_qty) <= qty_tol:
                qty_match = True
            
            # Check Price (unit_pretax_amount preferred, fallback to unit_amount)
            p = item.get('unit_pretax_amount')
            if p is None:
                p = item.get('unit_amount')
            
            if p is not None:
                p = float(p)
                if abs(p - expected_price) <= price_tol:
                    price_match = True
        
        if qty_match:
            score += 20
            feedback_parts.append(f"Quantity correct ({expected_qty}).")
        else:
            feedback_parts.append(f"Incorrect quantity found (expected {expected_qty}).")
            
        if price_match:
            score += 20
            feedback_parts.append(f"Unit price correct ({expected_price}).")
        else:
            feedback_parts.append(f"Incorrect price found (expected {expected_price}).")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }