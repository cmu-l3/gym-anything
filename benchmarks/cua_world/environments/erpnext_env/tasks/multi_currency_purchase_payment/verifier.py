#!/usr/bin/env python3
"""
Verifier for multi_currency_purchase_payment task.

Verification Strategy:
  C1: A Purchase Invoice exists for the supplier in EUR (docstatus=1).
  C2: The PI has the correct amounts (Total ≈ 1000 EUR, conversion rate ≈ 1.10).
  C3: A Payment Entry exists for the supplier (docstatus=1).
  C4: The PE has the updated exchange rate (~1.08).
  C5: The Purchase Invoice is fully paid (outstanding amount ≈ 0).

The script uses `copy_from_env` to safely retrieve the JSON results exported by `export_result.sh`.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_multi_currency_purchase_payment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", "/tmp/multi_currency_purchase_payment_result.json")
    
    local_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    local_tmp.close()

    try:
        copy_from_env(result_file, local_tmp.name)
        with open(local_tmp.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve or parse exported result data: {e}"
        }
    finally:
        if os.path.exists(local_tmp.name):
            os.unlink(local_tmp.name)

    pi_list = data.get("purchase_invoices", [])
    pe_list = data.get("payment_entries", [])

    score = 0
    feedback_parts = []

    # C1: Purchase Invoice submitted in EUR
    best_pi = None
    for pi in pi_list:
        if pi.get("currency") == "EUR" and pi.get("docstatus") == 1:
            best_pi = pi
            break

    if best_pi:
        score += 20
        feedback_parts.append(f"C1 PASS: PI '{best_pi['name']}' submitted in EUR (+20)")
    else:
        feedback_parts.append("C1 FAIL: No submitted PI in EUR found for Schmidt Industrietechnik GmbH")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # C2: Purchase Invoice Amounts Check
    grand_total = float(best_pi.get("grand_total", 0))
    base_grand_total = float(best_pi.get("base_grand_total", 0))
    conv_rate = float(best_pi.get("conversion_rate", 0))

    if abs(grand_total - 1000) <= 50 and abs(conv_rate - 1.10) <= 0.02:
        score += 25
        feedback_parts.append(f"C2 PASS: PI amounts correct (Total: €{grand_total}, Rate: {conv_rate}) (+25)")
    else:
        feedback_parts.append(f"C2 FAIL: PI amounts incorrect (Total: €{grand_total}, Rate: {conv_rate})")

    # C3: Payment Entry exists
    c3_pass = len(pe_list) > 0
    if c3_pass:
        score += 25
        feedback_parts.append(f"C3 PASS: Payment Entry submitted for supplier (+25)")
    else:
        feedback_parts.append("C3 FAIL: No submitted Payment Entry found for supplier")

    # C4: Exchange Rate updated in Payment Entry
    c4_pass = False
    for pe in pe_list:
        src_rate = float(pe.get("source_exchange_rate", 0))
        tgt_rate = float(pe.get("target_exchange_rate", 0))
        # Account for either direction rate depending on UI selection
        if abs(src_rate - 1.08) <= 0.02 or abs(tgt_rate - 1.08) <= 0.02:
            c4_pass = True
            break

    if c4_pass:
        score += 15
        feedback_parts.append("C4 PASS: Payment Entry exchange rate successfully modified to 1.08 (+15)")
    else:
        if pe_list:
            rates = [(pe.get("source_exchange_rate"), pe.get("target_exchange_rate")) for pe in pe_list]
            feedback_parts.append(f"C4 FAIL: Exchange rate not modified to 1.08 in PE (found rates: {rates})")
        else:
            feedback_parts.append("C4 FAIL: Cannot check PE exchange rate as no PE was submitted")

    # C5: Purchase Invoice is fully paid
    outstanding = float(best_pi.get("outstanding_amount", 1000))
    if outstanding <= 5:
        score += 15
        feedback_parts.append("C5 PASS: Purchase Invoice is fully paid (+15)")
    else:
        feedback_parts.append(f"C5 FAIL: Purchase Invoice outstanding amount is {outstanding} (not fully paid)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }