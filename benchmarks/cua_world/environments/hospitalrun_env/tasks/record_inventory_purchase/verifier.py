#!/usr/bin/env python3
"""
Verifier for record_inventory_purchase task.
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_inventory_purchase(traj, env_info, task_info):
    """
    Verifies that a purchase was recorded for the specific inventory item.
    
    Criteria:
    1. Item Quantity Updated: Should be 700 (200 initial + 500 added).
    2. Purchase Record Exists: Within the item's 'purchases' array (or linked docs).
       HospitalRun typically updates the 'purchases' array inside the 'data' object of the inventory doc.
    3. Purchase Details Match: Vendor, Cost, Lot, Invoice.
    """
    
    # 1. Setup: Load result data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_vendor = metadata.get("expected_vendor", "MedLine Industries")
    expected_cost = metadata.get("expected_cost", 625)
    expected_qty_added = metadata.get("expected_quantity_added", 500)
    expected_lot = metadata.get("expected_lot", "LOT-2024-0847")
    expected_invoice = metadata.get("expected_invoice", "INV-ML-20241115")
    expected_final_total = metadata.get("expected_final_quantity", 700)

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Parse Document
    doc = result.get("item_document", {})
    
    # HospitalRun structures data inside a "data" key usually, but sometimes top level depending on version/API
    # The setup script seeded it inside "data".
    data = doc.get("data", doc)
    
    # 3. Verify Total Quantity (30 points)
    current_qty = data.get("quantity")
    
    score = 0
    feedback_parts = []
    
    # Allow small tolerance if agent did partial work, but exact expected is 700
    try:
        current_qty = float(current_qty)
    except (ValueError, TypeError):
        current_qty = 0

    if current_qty == expected_final_total:
        score += 30
        feedback_parts.append(f"Total quantity updated correctly to {int(current_qty)}")
    elif current_qty > 200:
        # Partial credit if it increased but maybe wrong amount
        score += 10
        feedback_parts.append(f"Total quantity increased to {int(current_qty)}, expected {expected_final_total}")
    else:
        feedback_parts.append(f"Total quantity NOT updated (Current: {int(current_qty)})")

    # 4. Verify Purchase Record Details (70 points)
    # HospitalRun stores purchases in a 'purchases' list inside the inventory item
    purchases = data.get("purchases", [])
    
    # Find the matching purchase
    target_purchase = None
    for p in purchases:
        # Check for our specific identifiers
        p_lot = p.get("lotNumber", "")
        p_inv = p.get("invoiceNumber", "")
        p_vendor = p.get("vendor", "")
        
        # Loose matching to be robust
        if (expected_lot in p_lot) or (expected_invoice in p_inv) or (expected_vendor.lower() in p_vendor.lower()):
            target_purchase = p
            break
            
    if not target_purchase:
        return {
            "passed": False,
            "score": score,
            "feedback": "No purchase record found matching Vendor, Lot, or Invoice. " + " | ".join(feedback_parts)
        }
    
    score += 20 # Found the record
    feedback_parts.append("Purchase record found")
    
    # Check details
    # Vendor (10 pts)
    p_vendor = target_purchase.get("vendor", "")
    if expected_vendor.lower() in p_vendor.lower():
        score += 10
        feedback_parts.append("Vendor correct")
    else:
        feedback_parts.append(f"Vendor mismatch ('{p_vendor}')")
        
    # Cost (10 pts)
    p_cost = target_purchase.get("cost", 0)
    p_price = target_purchase.get("price", 0) # field might vary
    try:
        p_cost = float(p_cost) if p_cost else float(p_price)
    except:
        p_cost = 0
        
    if abs(p_cost - expected_cost) < 5:
        score += 10
        feedback_parts.append("Cost correct")
    else:
        feedback_parts.append(f"Cost mismatch ({p_cost})")

    # Quantity of purchase (10 pts)
    p_qty = target_purchase.get("quantity", 0)
    try:
        p_qty = float(p_qty)
    except:
        p_qty = 0
        
    if p_qty == expected_qty_added:
        score += 10
        feedback_parts.append("Purchase quantity correct")
    else:
        feedback_parts.append(f"Purchase quantity mismatch ({p_qty})")

    # Lot / Invoice (10 pts each)
    if expected_lot in target_purchase.get("lotNumber", ""):
        score += 10
        feedback_parts.append("Lot number correct")
    
    if expected_invoice in target_purchase.get("invoiceNumber", ""):
        score += 10
        feedback_parts.append("Invoice number correct")

    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }