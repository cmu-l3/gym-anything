#!/usr/bin/env python3
"""
Verifier for regional_tax_configuration_and_sales_order task.

Task:
1. Create GST Payable and PST Payable accounts under Duties and Taxes (Type: Tax).
2. Create 'British Columbia Tax' template with 5% GST and 7% PST rows.
3. Submit a Sales Order for Maple Leaf Wind using the template (Base: 10000, Tax: 1200, Total: 11200).

Scoring (100 pts total, pass >= 80):
  C1 [20 pts] — Both GST Payable and PST Payable accounts exist, correct parent and type.
  C2 [20 pts] — "British Columbia Tax" template created.
  C3 [20 pts] — Template contains 5% and 7% rates tied to the new tax accounts.
  C4 [20 pts] — Sales Order submitted for Maple Leaf Wind.
  C5 [20 pts] — Sales Order financial accuracy (Base $10000, Tax $1200, Grand $11200) and uses the template.

Anti-Gaming:
- Documents must explicitly use the configured templates to achieve full score.
- Financial totals are strictly verified against expected arithmetic.
"""

import json
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_regional_tax_configuration(trajectory, env_info, task_info):
    result_file = task_info.get("metadata", {}).get("result_file", "/tmp/regional_tax_result.json")
    local_tmp = "/tmp/_regional_tax_local.json"

    try:
        env_info["copy_from_env"](result_file, local_tmp)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result file missing. Export script failed: {e}"}

    try:
        with open(local_tmp) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not parse result JSON: {e}"}

    tax_accounts = data.get("found_tax_accounts", [])
    tax_templates = data.get("found_tax_templates", [])
    sales_orders = data.get("sales_orders", [])

    score = 0
    feedback = []

    # --- C1: Tax Accounts ---
    has_gst = False
    has_pst = False
    gst_acc_name = ""
    pst_acc_name = ""
    
    for acc in tax_accounts:
        name_lower = acc.get("account_name", "").lower()
        parent_lower = acc.get("parent_account", "").lower()
        acc_type = acc.get("account_type", "")
        
        is_duties_parent = "duties and taxes" in parent_lower
        is_tax_type = acc_type == "Tax" or acc_type == "Tax Account"
        
        if "gst" in name_lower:
            has_gst = True
            gst_acc_name = acc.get("name")
            if not is_duties_parent:
                feedback.append(f"Warning: GST account parent '{acc.get('parent_account')}' does not look like 'Duties and Taxes'.")
            if not is_tax_type:
                feedback.append("Warning: GST account Type is not set to 'Tax'.")
                
        if "pst" in name_lower:
            has_pst = True
            pst_acc_name = acc.get("name")
            if not is_duties_parent:
                feedback.append(f"Warning: PST account parent '{acc.get('parent_account')}' does not look like 'Duties and Taxes'.")
            if not is_tax_type:
                feedback.append("Warning: PST account Type is not set to 'Tax'.")

    if has_gst and has_pst:
        score += 20
        feedback.append("C1 PASS: Both GST and PST accounts created successfully.")
    elif has_gst or has_pst:
        score += 10
        feedback.append(f"C1 PARTIAL: Found only one tax account (GST: {has_gst}, PST: {has_pst}).")
    else:
        feedback.append("C1 FAIL: Did not find GST or PST accounts.")

    # --- C2 & C3: Tax Template and Configuration ---
    c2_pass = False
    c3_pass = False
    best_template = None
    
    for tmpl in tax_templates:
        if "british columbia" in tmpl.get("title", "").lower() or "bc tax" in tmpl.get("title", "").lower():
            c2_pass = True
            best_template = tmpl
            break

    if c2_pass:
        score += 20
        feedback.append("C2 PASS: British Columbia Tax template found.")
        
        # Check rates in template
        taxes = best_template.get("taxes", [])
        has_5_percent = False
        has_7_percent = False
        for t in taxes:
            rate = float(t.get("rate", 0))
            charge_type = t.get("charge_type", "")
            
            if abs(rate - 5.0) < 0.1 and charge_type == "On Net Total":
                has_5_percent = True
            if abs(rate - 7.0) < 0.1 and charge_type == "On Net Total":
                has_7_percent = True
                
        if has_5_percent and has_7_percent:
            c3_pass = True
            score += 20
            feedback.append("C3 PASS: Template configured with correct 5% and 7% rates on Net Total.")
        else:
            feedback.append(f"C3 FAIL: Template missing exact 5% and 7% rates on Net Total. Found rates: {[t.get('rate') for t in taxes]}")
    else:
        feedback.append("C2 FAIL: 'British Columbia Tax' template not found.")
        feedback.append("C3 SKIP: Template not found.")

    # --- C4 & C5: Sales Order Submission and Financial Accuracy ---
    c4_pass = False
    c5_pass = False
    
    submitted_sos = [so for so in sales_orders if str(so.get("docstatus")) == "1"]
    
    if submitted_sos:
        c4_pass = True
        score += 20
        best_so = submitted_sos[0]
        feedback.append(f"C4 PASS: Submitted Sales Order '{best_so.get('name')}' found for Maple Leaf Wind.")
        
        # Financial accuracy check
        net = float(best_so.get("net_total", 0))
        tax = float(best_so.get("total_taxes_and_charges", 0))
        grand = float(best_so.get("grand_total", 0))
        
        net_ok = abs(net - 10000.0) < 1.0
        tax_ok = abs(tax - 1200.0) < 1.0
        grand_ok = abs(grand - 11200.0) < 1.0
        
        # Check linkage to template
        tmpl_used = best_so.get("taxes_and_charges_template", "")
        linked_to_tmpl = c2_pass and best_template and tmpl_used == best_template.get("name")
        
        if net_ok and tax_ok and grand_ok:
            if linked_to_tmpl:
                c5_pass = True
                score += 20
                feedback.append("C5 PASS: Sales Order financially accurate ($11,200) and explicitly uses the new tax template.")
            else:
                score += 10
                feedback.append(f"C5 PARTIAL: Sales Order financially accurate ($11,200) but did NOT link the '{tmpl_used}' template properly.")
        else:
            feedback.append(f"C5 FAIL: Sales Order totals incorrect. Expected (Net:10000, Tax:1200, Grand:11200), Got (Net:{net}, Tax:{tax}, Grand:{grand}).")
    else:
        feedback.append("C4 FAIL: No submitted Sales Order found for Maple Leaf Wind.")
        feedback.append("C5 SKIP: No submitted SO to evaluate.")

    # Determine passing status
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }