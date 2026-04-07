#!/usr/bin/env python3
"""
Verifier for create_vendor_invoice@1 task.
Verifies creation of an AP Invoice in iDempiere using database records exported from the container.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_vendor_invoice(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the vendor invoice creation task.
    
    Scoring Criteria (Total 100):
    1. Invoice Created (20 pts): A new AP invoice exists in the system created during task time.
    2. Correct Vendor (15 pts): Business Partner is "Seed Farm Inc.".
    3. Invoice Completed (20 pts): DocStatus is 'CO' (Completed).
    4. Line Items Accuracy (30 pts):
       - Azalea Bush (Qty 25, Price 10)
       - Oak Tree (Qty 10, Price 50)
    5. Grand Total (15 pts): Exactly 750.00.
    """
    
    # 1. Setup access to container file
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    found_invoice = result_data.get('found_invoice')
    initial_count = int(result_data.get('initial_count', 0))
    current_count = int(result_data.get('current_count', 0))
    
    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Invoice Created (20 pts) ---
    if found_invoice:
        score += 20
        feedback_parts.append("✅ New invoice record found")
    elif current_count > initial_count:
        # Fallback: Count increased but our specific query for Seed Farm didn't find it 
        # (maybe wrong vendor used). We give partial points for creating *something*.
        score += 10
        feedback_parts.append("⚠️ Invoice count increased, but specific Seed Farm invoice not found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    else:
        return {"passed": False, "score": 0, "feedback": "❌ No new invoice created"}

    # At this point we have 'found_invoice' which matches Seed Farm Inc.
    
    # --- Criterion 2: Correct Vendor (15 pts) ---
    # Our SQL query specifically filtered for 'Seed Farm Inc.', so if found_invoice exists, this is true.
    # We verify explicitly just to be safe.
    vendor_name = found_invoice.get('bpartner_name', '')
    if 'Seed Farm' in vendor_name:
        score += 15
        feedback_parts.append(f"✅ Correct Vendor ({vendor_name})")
    else:
        feedback_parts.append(f"❌ Incorrect Vendor ({vendor_name})")

    # --- Criterion 3: Invoice Completed (20 pts) ---
    doc_status = found_invoice.get('docstatus', '')
    if doc_status == 'CO':
        score += 20
        feedback_parts.append("✅ Invoice Completed")
    elif doc_status == 'DR':
        score += 5
        feedback_parts.append("⚠️ Invoice saved but in Draft status (not Completed)")
    else:
        feedback_parts.append(f"❌ Invoice status incorrect: {doc_status}")

    # --- Criterion 4: Line Items Accuracy (30 pts) ---
    lines = found_invoice.get('lines', [])
    if lines is None: lines = []
    
    # Helper to find line
    def find_line(product_name):
        for line in lines:
            if product_name.lower() in line.get('product_name', '').lower():
                return line
        return None

    # Check Azalea (15 pts)
    azalea = find_line("Azalea Bush")
    if azalea:
        qty = float(azalea.get('qtyinvoiced', 0))
        price = float(azalea.get('priceactual', 0))
        if qty == 25 and price == 10.0:
            score += 15
            feedback_parts.append("✅ Azalea Bush line correct")
        else:
            score += 5 # Partial for finding product
            feedback_parts.append(f"⚠️ Azalea Bush details mismatch (Qty: {qty}, Price: {price})")
    else:
        feedback_parts.append("❌ Azalea Bush line missing")

    # Check Oak Tree (15 pts)
    oak = find_line("Oak Tree")
    if oak:
        qty = float(oak.get('qtyinvoiced', 0))
        price = float(oak.get('priceactual', 0))
        if qty == 10 and price == 50.0:
            score += 15
            feedback_parts.append("✅ Oak Tree line correct")
        else:
            score += 5 # Partial
            feedback_parts.append(f"⚠️ Oak Tree details mismatch (Qty: {qty}, Price: {price})")
    else:
        feedback_parts.append("❌ Oak Tree line missing")

    # --- Criterion 5: Grand Total (15 pts) ---
    grand_total = float(found_invoice.get('grandtotal', 0))
    expected_total = 750.00
    if abs(grand_total - expected_total) < 0.01:
        score += 15
        feedback_parts.append(f"✅ Grand Total correct (${grand_total})")
    else:
        feedback_parts.append(f"❌ Grand Total incorrect (${grand_total}, expected $750.00)")

    # 3. Final Evaluation
    passed = score >= 70  # Pass threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }