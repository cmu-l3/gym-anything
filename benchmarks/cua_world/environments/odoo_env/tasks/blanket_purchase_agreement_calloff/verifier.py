#!/usr/bin/env python3
"""
Verifier for blanket_purchase_agreement_calloff task.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_blanket_purchase_agreement_calloff(traj, env_info, task_info):
    """
    Verify:
    1. Purchase Agreements feature enabled (module installed).
    2. Blanket Order created for correct Vendor/Product/Qty/Price.
    3. Call-off PO created linked to Agreement with correct Qty/Price.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        copy_from_env('/tmp/blanket_purchase_agreement_calloff_result.json', temp_file.name)
        with open(temp_file.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    score = 0
    feedback = []

    setup = result['setup']
    target_product_id = setup['product_id']
    target_qty = 1000.0
    target_price = 42.00
    calloff_qty = 50.0

    # 1. Feature Enabled (10 pts)
    if result.get('module_status') == 'installed':
        score += 10
        feedback.append("Purchase Agreements feature enabled (10/10)")
    else:
        feedback.append("Purchase Agreements module not installed (0/10)")

    # 2. Blanket Order Agreement (40 pts)
    # Looking for: Vendor correct (filtered in export), Product correct, Price correct, Qty correct, State confirmed
    valid_agreement = None
    
    for ag in result.get('agreements', []):
        # Check lines
        for line in ag.get('lines_details', []):
            p_id = line['product_id'][0] if isinstance(line['product_id'], list) else line['product_id']
            qty = line.get('product_qty', 0)
            price = line.get('price_unit', 0)
            
            if p_id == target_product_id:
                # Check specifics
                ag_score = 0
                
                # Check State (Confirming agreement)
                if ag['state'] in ['ongoing', 'open']:
                    ag_score += 10
                
                # Check details
                if abs(qty - target_qty) < 1.0:
                    ag_score += 10
                if abs(price - target_price) < 0.01:
                    ag_score += 10
                
                # Base points for finding the agreement shell
                ag_score += 10
                
                if ag_score >= 40: # Perfect agreement
                    valid_agreement = ag
                    score += 40
                    feedback.append("Correct Blanket Order Agreement found and confirmed (40/40)")
                    break
                else:
                    # Partial credit logic could go here, but let's keep it strict or take the best one
                    valid_agreement = ag # Take the last one matching product
                    
    if not valid_agreement:
        feedback.append("No valid Blanket Order found for the target product (0/40)")
    elif score < 50: # If we didn't hit the perfect break above
        # Recalculate based on valid_agreement capture
        this_score = 10 # Base
        for line in valid_agreement.get('lines_details', []):
             p_id = line['product_id'][0] if isinstance(line['product_id'], list) else line['product_id']
             if p_id == target_product_id:
                 if valid_agreement['state'] in ['ongoing', 'open']: this_score += 10
                 if abs(line.get('product_qty', 0) - target_qty) < 1.0: this_score += 10
                 if abs(line.get('price_unit', 0) - target_price) < 0.01: this_score += 10
        score += this_score
        feedback.append(f"Blanket Order found but with issues (score: {this_score}/40)")

    # 3. Call-off Purchase Order (50 pts)
    # Must be linked to the agreement found (or any agreement), have correct qty, price, and be confirmed
    valid_po = None
    po_score_max = 0
    
    for po in result.get('orders', []):
        # Check if linked to our valid agreement
        req_id = po['requisition_id'][0] if isinstance(po['requisition_id'], list) else po['requisition_id']
        
        if valid_agreement and req_id == valid_agreement['id']:
            # Check lines
            for line in po.get('lines_details', []):
                p_id = line['product_id'][0] if isinstance(line['product_id'], list) else line['product_id']
                qty = line.get('product_qty', 0)
                price = line.get('price_unit', 0)
                
                if p_id == target_product_id:
                    current_po_score = 0
                    
                    # Linkage (already checked)
                    current_po_score += 15
                    
                    # Qty
                    if abs(qty - calloff_qty) < 0.5:
                        current_po_score += 10
                    
                    # Price (Should inherit from agreement)
                    if abs(price - target_price) < 0.01:
                        current_po_score += 15
                        
                    # State
                    if po['state'] in ['purchase', 'done']:
                        current_po_score += 10
                        
                    if current_po_score > po_score_max:
                        po_score_max = current_po_score
                        valid_po = po

    score += po_score_max
    if po_score_max > 0:
        feedback.append(f"Call-off Purchase Order processed (score: {po_score_max}/50)")
    else:
        feedback.append("No valid Call-off Order found linked to the agreement (0/50)")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }