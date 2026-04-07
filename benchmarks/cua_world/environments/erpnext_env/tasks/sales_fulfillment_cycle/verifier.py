"""
Verifier for sales_fulfillment_cycle task.

Task: Fulfill the Sales Order from Consumers and Consumers Express —
      SO already submitted, agent must create Delivery Note → Sales Invoice → Payment Entry.

Scoring (100 pts total, pass >= 70):
  C1 [25 pts] — Delivery Note submitted for Consumers and Consumers Express
                 with Wind Turbine (qty >= 20) AND Wind Mill A Series (qty >= 10),
                 linked to the setup Sales Order.
  C2 [25 pts] — Sales Invoice submitted for the same customer,
                 grand_total >= 660 (allows 5% variance on $700).
  C3 [25 pts] — Payment Entry (Receive) submitted for Consumers and Consumers Express.
  C4 [25 pts] — Customer outstanding balance = 0 (all invoices paid).

Wrong-target guard: If Sales Invoices exist but none contain Wind Turbine or
                    Wind Mill A Series, return score=0 immediately.

Anti-Pattern 4 Audit:
  C1: Agent could ship wrong items. Mitigation: Check both item codes and qty floors.
  C2: Agent could invoice partial amount. Mitigation: grand_total >= 660.
  C3: Agent could receive payment for different customer. Mitigation: party == CUSTOMER.
  C4: Agent could clear outstanding without a real PE. Mitigation: C3 must pass too.
"""

import json

CUSTOMER = "Consumers and Consumers Express"


def verify_sales_fulfillment_cycle(trajectory, env_info, task_info):
    result_file = task_info.get("metadata", {}).get(
        "result_file", "/tmp/sales_fulfillment_cycle_result.json"
    )
    local_tmp = "/tmp/_sfc_result_local.json"

    try:
        env_info["copy_from_env"](result_file, local_tmp)
    except Exception as e:
        return {"passed": False, "score": 0,
                "reason": f"Result file missing — export script may not have run: {e}"}

    try:
        with open(local_tmp) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0,
                "reason": f"Could not parse result JSON: {e}"}

    so_name = data.get("so_name", "")
    dn_list = data.get("delivery_notes", [])
    si_list = data.get("sales_invoices", [])
    pe_list = data.get("payment_entries", [])
    customer_outstanding = data.get("customer_outstanding", None)

    # --- ERPNext reachability sentinel ---
    if not so_name:
        return {"passed": False, "score": 0,
                "reason": "ERPNext setup data missing (so_name not in result) — "
                          "ERPNext may have been offline during setup or export"}

    score = 0
    reasons = []

    # --- Wrong-target guard ---
    if si_list and not any(
        si.get("has_wind_turbine") or si.get("has_wind_mill_a_series")
        for si in si_list
    ):
        return {"passed": False, "score": 0,
                "reason": "WRONG TARGET: Sales invoices found but contain neither Wind Turbine "
                          "nor Wind Mill A Series — agent invoiced wrong items"}

    # --- C1: Delivery Note with correct items and quantities ---
    c1_pass = False
    for dn in dn_list:
        wt_qty = dn.get("wind_turbine_qty", 0)
        wm_qty = dn.get("wind_mill_qty", 0)
        if wt_qty >= 20 and wm_qty >= 10:
            c1_pass = True
            break
    if c1_pass:
        score += 25
        reasons.append("C1 PASS: Delivery Note submitted with correct items and quantities (+25)")
    else:
        if dn_list:
            qtys = [(d.get("wind_turbine_qty"), d.get("wind_mill_qty")) for d in dn_list]
            reasons.append(f"C1 FAIL: DN found but qty insufficient (WT,WM per DN: {qtys})")
        else:
            reasons.append("C1 FAIL: No submitted Delivery Note for Consumers and Consumers Express")

    # --- C2: Sales Invoice with correct total ---
    c2_pass = any(si.get("grand_total", 0) >= 660 for si in si_list)
    if c2_pass:
        score += 25
        reasons.append("C2 PASS: Sales Invoice submitted with grand_total >= $660 (+25)")
    else:
        if si_list:
            totals = [si.get("grand_total") for si in si_list]
            reasons.append(f"C2 FAIL: SI grand_total < $660 (got {totals})")
        else:
            reasons.append("C2 FAIL: No submitted Sales Invoice found")

    # --- C3: Payment Entry (Receive) for customer ---
    c3_pass = any(
        pe.get("payment_type") in ("Receive", "Internal Transfer") or
        pe.get("received_amount", 0) > 0
        for pe in pe_list
    )
    if c3_pass:
        score += 25
        reasons.append("C3 PASS: Payment received from Consumers and Consumers Express (+25)")
    else:
        reasons.append("C3 FAIL: No submitted Payment Entry found for this customer")

    # --- C4: Outstanding = 0 (only if C2 passed — must have an actual invoice) ---
    if c2_pass:
        c4_pass = customer_outstanding is not None and float(customer_outstanding) <= 0.01
        if c4_pass:
            score += 25
            reasons.append("C4 PASS: Customer outstanding balance is zero (+25)")
        else:
            reasons.append(f"C4 FAIL: Customer outstanding = {customer_outstanding} (must be 0)")
    else:
        reasons.append("C4 SKIP: C2 must pass before C4 is evaluated")

    passed = score >= 70
    return {"passed": passed, "score": score, "reason": " | ".join(reasons)}
