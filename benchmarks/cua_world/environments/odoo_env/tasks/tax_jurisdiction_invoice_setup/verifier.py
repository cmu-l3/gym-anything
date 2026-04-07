#!/usr/bin/env python3
"""
Verifier for tax_jurisdiction_invoice_setup task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tax_jurisdiction_invoice_setup(traj, env_info, task_info):
    """
    Verifies that:
    1. A tax with rate 8.875% was created.
    2. Products were assigned this tax.
    3. An invoice was created with correct lines and totals.
    4. The invoice is posted.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        copy_from_env('/tmp/tax_task_result.json', temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Setup/Export Error: {result['error']}"}

    score = 0
    feedback = []

    # 1. Check Tax Creation (20 pts)
    found_tax = result.get('found_tax')
    tax_id = None
    if found_tax:
        score += 15
        feedback.append("Tax with 8.875% rate found.")
        tax_id = found_tax['id']
        
        if "NY" in found_tax['name'] or "New York" in found_tax['name']:
            score += 5
            feedback.append("Tax name contains location identifier.")
    else:
        feedback.append("No tax with 8.875% rate found.")

    # 2. Check Product Assignment (20 pts)
    prod_status = result.get('product_status', {})
    products_ok = 0
    for name, status in prod_status.items():
        if status.get('has_target_tax'):
            products_ok += 1
    
    if products_ok == 2:
        score += 20
        feedback.append("Both products have the new tax assigned.")
    elif products_ok == 1:
        score += 10
        feedback.append("Only one product has the new tax assigned.")
    else:
        feedback.append("Products do not have the new tax assigned.")

    # 3. Check Invoice Existence and Lines (20 pts)
    invoice = result.get('invoice')
    analysis = result.get('invoice_analysis', {})
    
    if invoice:
        score += 10
        feedback.append("Invoice found for customer.")
        
        if analysis.get('correct_lines'):
            score += 10
            feedback.append("Invoice has correct product quantities.")
        else:
            feedback.append("Invoice product quantities are incorrect.")
    else:
        feedback.append("No invoice found for customer.")

    # 4. Check Invoice Totals and Tax Application (25 pts)
    # Expected: Subtotal 5330, Tax ~473.04
    if invoice:
        amount_total = invoice.get('amount_total', 0)
        amount_tax = invoice.get('amount_tax', 0)
        
        # Tolerance check
        expected_total = 5803.04
        expected_tax = 473.04
        
        if abs(amount_total - expected_total) < 1.0:
            score += 15
            feedback.append(f"Invoice total correct (${amount_total}).")
        else:
            feedback.append(f"Invoice total incorrect (Expected ${expected_total}, Got ${amount_total}).")
            
        if abs(amount_tax - expected_tax) < 1.0:
            score += 10
            feedback.append(f"Invoice tax amount correct (${amount_tax}).")
        elif found_tax and analysis.get('lines_have_target_tax'):
             # If exact amount is off due to rounding settings but tax is linked, give partial
             score += 5
             feedback.append("Tax linked to lines but amount mismatch (rounding difference?).")

    # 5. Check Invoice Posted (15 pts)
    if analysis.get('posted'):
        score += 15
        feedback.append("Invoice is posted.")
    else:
        feedback.append("Invoice is in Draft state (not posted).")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }