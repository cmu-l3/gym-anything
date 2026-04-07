#!/usr/bin/env python3
"""
Verifier for sales_pricelist_cost_plus_formula@1

Grading Criteria:
1. Pricelist "Wholesale Plus" exists (20 pts)
2. Formula Rule Configured Correctly (40 pts)
   - Compute Price = Formula
   - Base = Cost (standard_price)
   - Discount = -20 (Markup 20%)
   - Surcharge = 5
3. Quotation Created with Pricelist (20 pts)
4. Correct Calculated Unit Price ($29.00) (20 pts)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sales_pricelist_cost_plus_formula(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_price = float(metadata.get('expected_price', 29.0))
    expected_markup = float(metadata.get('markup_pct', 20))
    expected_surcharge = float(metadata.get('surcharge', 5.0))
    
    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/pricelist_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback = []
    
    # 1. Pricelist Exists
    if result.get('pricelist_found'):
        score += 20
        feedback.append("Pricelist 'Wholesale Plus' created.")
    else:
        feedback.append("Pricelist 'Wholesale Plus' NOT found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}
        
    # 2. Formula Configuration
    # We need to find at least one item that matches the formula
    items = result.get('items', [])
    formula_correct = False
    
    for item in items:
        # compute_price: 'formula'
        # base: 'standard_price' (Cost)
        # price_discount: -20 (Note: Odoo stores 20% markup as -20 discount)
        # price_surcharge: 5
        
        is_formula = item.get('compute_price') == 'formula'
        is_cost_base = item.get('base') == 'standard_price'
        
        # Check discount (markup) - allow small float tolerance
        discount = float(item.get('price_discount', 0))
        markup_ok = abs(discount - (-expected_markup)) < 0.1
        
        # Check surcharge
        surcharge = float(item.get('price_surcharge', 0))
        surcharge_ok = abs(surcharge - expected_surcharge) < 0.1
        
        if is_formula and is_cost_base and markup_ok and surcharge_ok:
            formula_correct = True
            break
            
    if formula_correct:
        score += 40
        feedback.append("Formula rule configured correctly (Cost + 20% + $5).")
    else:
        feedback.append("Formula rule INCORRECT. Checked items: " + str(items))
        
    # 3. Quotation Created
    if result.get('order_found'):
        score += 20
        feedback.append("Quotation created for 'Azure Interior' using the pricelist.")
    else:
        feedback.append("Quotation NOT found or not linked to the pricelist/customer.")
        
    # 4. Price Calculation
    line_data = result.get('line')
    price_correct = False
    if line_data:
        unit_price = float(line_data.get('price_unit', 0))
        if abs(unit_price - expected_price) < 0.1:
            price_correct = True
            score += 20
            feedback.append(f"Unit price calculated correctly: ${unit_price}.")
        else:
            feedback.append(f"Unit price incorrect. Expected ${expected_price}, got ${unit_price}.")
    else:
        feedback.append("Product line not found in quotation.")
        
    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " ".join(feedback)
    }