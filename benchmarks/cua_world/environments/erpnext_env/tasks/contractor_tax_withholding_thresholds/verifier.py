#!/usr/bin/env python3
"""
Verifier for contractor_tax_withholding_thresholds task.

Task:
1. Create a Tax Withholding Category ('Contractor TDS 15%') with rate=15, threshold=5000, linked to 'TDS Payable - WP'.
2. Assign it to supplier 'Build-It Construction'.
3. Submit a Purchase Invoice for $4,000 (no tax).
4. Submit a Purchase Invoice for $6,000 (tax withheld).

Scoring (100 pts total, pass >= 70):
- C1 [20 pts]: Tax Category properly setup.
- C2 [10 pts]: Supplier linked to category.
- C3 [20 pts]: $4,000 invoice exists with no tax withheld.
- C4 [20 pts]: $6,000 invoice exists with $900 tax withheld.
- C5 [30 pts]: GL entries for the $6,000 invoice show correct credit to TDS Payable.
"""

import json

def verify_contractor_tax(trajectory, env_info, task_info):
    result_file = task_info.get("metadata", {}).get(
        "result_file", "/tmp/contractor_tax_result.json"
    )
    local_tmp = "/tmp/_contractor_tax_result_local.json"

    try:
        env_info["copy_from_env"](result_file, local_tmp)
    except Exception as e:
        return {"passed": False, "score": 0,
                "feedback": f"Result file missing — export script may not have run: {e}"}

    try:
        with open(local_tmp) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0,
                "feedback": f"Could not parse result JSON: {e}"}

    tax_categories = data.get("tax_categories", [])
    supplier_tax_category = data.get("supplier_tax_category", "")
    purchase_invoices = data.get("purchase_invoices", [])
    gl_entries = data.get("gl_entries", [])
    
    score = 0
    feedback = []

    # --- C1: Tax Category Setup (20 pts) ---
    c1_pass = False
    valid_category_name = None
    for cat in tax_categories:
        rates = cat.get("rates", [])
        accounts = cat.get("accounts", [])
        
        has_correct_rate = any(
            float(r.get("tax_withholding_rate", 0) or 0) == 15.0 and 
            float(r.get("single_transaction_threshold", 0) or 0) == 5000.0
            for r in rates
        )
        
        has_correct_account = any(
            a.get("account") == "TDS Payable - WP" 
            for a in accounts
        )
        
        if has_correct_rate and has_correct_account:
            c1_pass = True
            valid_category_name = cat.get("name")
            break

    if c1_pass:
        score += 20
        feedback.append(f"C1 PASS: Tax Withholding Category '{valid_category_name}' configured correctly (+20)")
    else:
        feedback.append("C1 FAIL: Could not find a Tax Withholding Category with 15% rate, 5000 threshold, and TDS Payable account")

    # --- C2: Supplier Linkage (10 pts) ---
    c2_pass = False
    if supplier_tax_category and (supplier_tax_category == valid_category_name or supplier_tax_category == "Contractor TDS 15%"):
        c2_pass = True
        score += 10
        feedback.append("C2 PASS: Supplier linked to Tax Withholding Category (+10)")
    elif supplier_tax_category:
        feedback.append(f"C2 FAIL: Supplier linked to wrong category ('{supplier_tax_category}')")
    else:
        feedback.append("C2 FAIL: Supplier 'Build-It Construction' not linked to any Tax Withholding Category")

    # --- Find PI-1 (Under Threshold ~ $4000) and PI-2 (Over Threshold ~ $6000) ---
    pi_under = None
    pi_over = None
    
    for pi in purchase_invoices:
        base = float(pi.get("base_total", 0))
        if 3900 <= base <= 4100:
            pi_under = pi
        elif 5900 <= base <= 6100:
            pi_over = pi

    # --- C3: PI-1 Under Threshold (20 pts) ---
    c3_pass = False
    if pi_under:
        # Should have NO tax withholding
        tax_rows = pi_under.get("taxes", [])
        has_tds = any("TDS" in str(t.get("account_head", "")) for t in tax_rows)
        if not has_tds and float(pi_under.get("grand_total", 0)) >= 3900:
            c3_pass = True
            score += 20
            feedback.append(f"C3 PASS: $4,000 Invoice '{pi_under.get('name')}' submitted with NO tax withheld (+20)")
        else:
            feedback.append("C3 FAIL: $4,000 Invoice submitted but taxes were improperly withheld")
    else:
        feedback.append("C3 FAIL: No submitted $4,000 Purchase Invoice found")

    # --- C4: PI-2 Over Threshold (20 pts) ---
    c4_pass = False
    if pi_over:
        # Should have ~$900 tax withholding (negative value in taxes or net total)
        tax_rows = pi_over.get("taxes", [])
        tds_amount = 0
        for t in tax_rows:
            if "TDS Payable" in str(t.get("account_head", "")):
                # Taxes are usually added, but TDS is a deduction, so it's a negative tax amount in PI
                # or positive depending on version. We'll use absolute value.
                tds_amount += abs(float(t.get("tax_amount", 0)))
        
        if 850 <= tds_amount <= 950:
            c4_pass = True
            score += 20
            feedback.append(f"C4 PASS: $6,000 Invoice '{pi_over.get('name')}' correctly withheld ~$900 tax (+20)")
        else:
            feedback.append(f"C4 FAIL: $6,000 Invoice found but TDS withheld was {tds_amount} (expected ~900)")
    else:
        feedback.append("C4 FAIL: No submitted $6,000 Purchase Invoice found")

    # --- C5: GL Entries Accuracy (30 pts) ---
    c5_pass = False
    if pi_over and c4_pass:
        pi_name = pi_over.get("name")
        relevant_gls = [g for g in gl_entries if g.get("voucher_no") == pi_name]
        
        tds_credit = 0
        for g in relevant_gls:
            if g.get("account") == "TDS Payable - WP":
                tds_credit += float(g.get("credit", 0))
                
        if 850 <= tds_credit <= 950:
            c5_pass = True
            score += 30
            feedback.append(f"C5 PASS: GL Entries for '{pi_name}' correctly credit TDS Payable by ~900 (+30)")
        else:
            feedback.append(f"C5 FAIL: GL Entries for '{pi_name}' credit TDS Payable by {tds_credit} (expected ~900)")
    else:
        feedback.append("C5 FAIL: Cannot verify GL entries because the $6,000 invoice with tax was not found")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }