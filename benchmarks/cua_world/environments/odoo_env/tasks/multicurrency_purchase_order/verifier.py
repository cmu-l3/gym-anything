#!/usr/bin/env python3
"""
Verifier for multicurrency_purchase_order task.

Scoring (100 points):
- Vendor 'Rhine Valley Components GmbH' created (company type): 10 pts
- Vendor country is Germany: 10 pts
- PO exists for vendor: 10 pts
- PO currency is EUR: 15 pts
- PO State is 'purchase' (confirmed) or 'done': 20 pts
- Line items match (Product + Qty + Price): 30 pts (15 per line)
- PO Total Amount correct: 5 pts

Pass Threshold: 65 points.
"""

import json
import logging
import tempfile
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_multicurrency_purchase_order(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Verify Vendor (20 pts)
    if result.get('vendor_found'):
        vendor = result['vendor']
        score += 10
        feedback.append("Vendor 'Rhine Valley Components GmbH' found.")
        
        # Check Country
        if vendor.get('country_name') == 'Germany':
            score += 10
            feedback.append("Vendor country correctly set to Germany.")
        else:
            feedback.append(f"Vendor country is '{vendor.get('country_name')}', expected 'Germany'.")
    else:
        feedback.append("Vendor 'Rhine Valley Components GmbH' NOT found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # 2. Verify PO Existence & Currency (25 pts)
    if result.get('po_found'):
        po = result['po']
        score += 10
        feedback.append("Purchase Order found.")

        # Check Currency
        if po.get('currency_name') == 'EUR':
            score += 15
            feedback.append("PO currency correctly set to EUR.")
        else:
            feedback.append(f"PO currency is '{po.get('currency_name')}', expected 'EUR'.")
            
        # 3. Verify State (20 pts)
        if po.get('state') in ['purchase', 'done']:
            score += 20
            feedback.append("PO is confirmed.")
        else:
            feedback.append(f"PO state is '{po.get('state')}', expected 'purchase' (confirmed).")

        # 4. Verify Lines (30 pts + 5 pts total)
        lines = po.get('lines', [])
        setup_products = result.get('setup_products', {})
        
        # Expected products and values
        # "Precision Bearing Assembly Type-K": 50 qty, 42.50 price
        # "Industrial Servo Motor Controller": 25 qty, 189.00 price
        
        # We match by product ID if available in setup, or fuzzy match name
        bearing_ok = False
        motor_ok = False
        
        bearing_id = setup_products.get('Precision Bearing Assembly Type-K')
        motor_id = setup_products.get('Industrial Servo Motor Controller')
        
        for line in lines:
            pid = line.get('product_id')
            qty = line.get('qty', 0)
            price = line.get('price_unit', 0)
            
            # Check Bearing
            if pid == bearing_id:
                if abs(qty - 50) < 0.1 and abs(price - 42.50) < 0.1:
                    bearing_ok = True
            
            # Check Motor
            if pid == motor_id:
                if abs(qty - 25) < 0.1 and abs(price - 189.00) < 0.1:
                    motor_ok = True
        
        if bearing_ok:
            score += 15
            feedback.append("Bearing line item correct.")
        else:
            feedback.append("Bearing line item incorrect (check product, qty 50, price 42.50).")
            
        if motor_ok:
            score += 15
            feedback.append("Motor line item correct.")
        else:
            feedback.append("Motor line item incorrect (check product, qty 25, price 189.00).")

        # Check total amount (5 pts)
        # 50*42.5 + 25*189 = 2125 + 4725 = 6850
        total = po.get('amount_total', 0)
        if abs(total - 6850.0) < 1.0:
            score += 5
            feedback.append("Total amount correct.")

    else:
        feedback.append("No Purchase Order found for this vendor.")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }