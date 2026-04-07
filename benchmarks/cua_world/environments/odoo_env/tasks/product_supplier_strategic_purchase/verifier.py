#!/usr/bin/env python3
"""
Verifier for product_supplier_strategic_purchase task.

Scoring (100 points):
- Supplier 1 (Allied) configured correctly: 15 pts
- Supplier 2 (Pacific) configured correctly: 15 pts
- Purchase Order created for correct vendor (Pacific): 15 pts
- Purchase Order confirmed: 15 pts
- PO Product correct: 10 pts
- PO Quantity correct (500): 15 pts
- PO Unit Price correct (~11.80): 15 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_product_supplier_strategic_purchase(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    v1_meta = metadata.get('vendor_1', {})
    v2_meta = metadata.get('vendor_2', {})
    target_vendor_name = metadata.get('target_vendor')
    target_price = metadata.get('target_price')
    order_qty = metadata.get('order_qty')

    # Get result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    try:
        try:
            copy_from_env('/tmp/task_result.json', temp_file.name)
            with open(temp_file.name) as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        os.unlink(temp_file.name)

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Export error: {result.get('error')}"}

    score = 0
    feedback_parts = []

    # Get IDs from setup
    setup_vendors = result.get('setup_vendors', {})
    id_allied = setup_vendors.get('Allied Industrial Supply Co.')
    id_pacific = setup_vendors.get('Pacific Bearing Solutions')

    configured_suppliers = result.get('configured_suppliers', [])
    purchase_orders = result.get('purchase_orders', [])
    variant_id = result.get('variant_id')

    # 1. Verify Supplier 1 Configuration (Allied)
    # Expected: Price 12.50, Min 100, Delay 14
    s1_found = False
    for s in configured_suppliers:
        if s['partner_id'] == id_allied:
            s1_found = True
            checks = []
            if abs(s['price'] - v1_meta['price']) < 0.1: checks.append(True)
            if s['min_qty'] == v1_meta['min_qty']: checks.append(True)
            if s['delay'] == v1_meta['delay']: checks.append(True)
            
            if all(checks):
                score += 15
                feedback_parts.append("Allied supplier info configured correctly (15/15)")
            else:
                score += 5 # Partial credit for adding vendor
                feedback_parts.append(f"Allied supplier info incorrect fields (found price={s['price']}, qty={s['min_qty']}, delay={s['delay']}) (5/15)")
            break
    if not s1_found:
        feedback_parts.append("Allied supplier info NOT found (0/15)")

    # 2. Verify Supplier 2 Configuration (Pacific)
    # Expected: Price 11.80, Min 250, Delay 21
    s2_found = False
    for s in configured_suppliers:
        if s['partner_id'] == id_pacific:
            s2_found = True
            checks = []
            if abs(s['price'] - v2_meta['price']) < 0.1: checks.append(True)
            if s['min_qty'] == v2_meta['min_qty']: checks.append(True)
            if s['delay'] == v2_meta['delay']: checks.append(True)
            
            if all(checks):
                score += 15
                feedback_parts.append("Pacific supplier info configured correctly (15/15)")
            else:
                score += 5
                feedback_parts.append(f"Pacific supplier info incorrect fields (found price={s['price']}, qty={s['min_qty']}, delay={s['delay']}) (5/15)")
            break
    if not s2_found:
        feedback_parts.append("Pacific supplier info NOT found (0/15)")

    # 3. Verify Purchase Order
    # Find the best candidate order
    best_po = None
    
    # Filter for orders with correct product
    valid_pos = [po for po in purchase_orders if po.get('product_id') == variant_id]
    
    # Check for correct vendor (Pacific)
    pacific_pos = [po for po in valid_pos if po.get('partner_id') == id_pacific]
    
    if pacific_pos:
        # Prioritize confirmed orders
        confirmed = [po for po in pacific_pos if po.get('state') in ['purchase', 'done']]
        best_po = confirmed[0] if confirmed else pacific_pos[0]
        
        score += 15
        feedback_parts.append("Purchase Order created for correct vendor (Pacific) (15/15)")
    else:
        # Check if they ordered from Allied instead
        allied_pos = [po for po in valid_pos if po.get('partner_id') == id_allied]
        if allied_pos:
            feedback_parts.append("Purchase Order created for WRONG vendor (Allied) - not cost effective (0/15)")
            best_po = allied_pos[0]
        else:
            feedback_parts.append("No relevant Purchase Order found (0/15)")

    if best_po:
        # Verify Product (already filtered by product_id in export, but double check)
        if best_po.get('product_id') == variant_id:
            score += 10
            feedback_parts.append("PO contains correct product (10/10)")
        
        # Verify Confirmation
        if best_po.get('state') in ['purchase', 'done']:
            score += 15
            feedback_parts.append("PO confirmed (15/15)")
        else:
            feedback_parts.append(f"PO in state '{best_po.get('state')}' (expected 'purchase') (0/15)")
            
        # Verify Quantity
        qty = best_po.get('qty', 0)
        if qty == order_qty:
            score += 15
            feedback_parts.append(f"PO quantity correct ({qty}) (15/15)")
        else:
            feedback_parts.append(f"PO quantity {qty} incorrect (expected {order_qty}) (0/15)")
            
        # Verify Price
        price = best_po.get('price_unit', 0.0)
        if abs(price - target_price) < 0.5:
            score += 15
            feedback_parts.append(f"PO unit price correct (${price}) (15/15)")
        else:
            feedback_parts.append(f"PO unit price ${price} incorrect (expected ${target_price}) (0/15)")

    # Final result
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }