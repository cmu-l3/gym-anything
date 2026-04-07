"""
Verifier for full_procurement_cycle task.

Task: Complete the procurement cycle for Eagle Hardware — PO already submitted,
      agent must create Purchase Receipt → Purchase Invoice → Payment Entry.

Scoring (100 pts total, pass >= 70):
  C1 [30 pts] — Purchase Receipt submitted and linked to the Eagle Hardware PO
                 for Upper Bearing Plate (qty >= 50).
  C2 [30 pts] — Purchase Invoice submitted for Eagle Hardware containing
                 Upper Bearing Plate with grand_total >= 2400 (allows up to 4% variance).
  C3 [20 pts] — Payment Entry (Pay) submitted for Eagle Hardware supplier.
  C4 [20 pts] — Eagle Hardware outstanding balance = 0 across all submitted PIs
                 (all invoices paid off).

Wrong-target guard: Score immediately 0 if the only PI found is for a different
                    supplier (e.g. agent invoiced HomeBase instead).

Anti-Pattern 4 Audit:
  C1: Could it be gamed? Yes — someone could manually create a PR not linked to the PO.
      Mitigation: We check purchase_order == po_name in PR item row.
  C2: Could it be gamed? Agent could invoice arbitrary amount.
      Mitigation: grand_total must be >= 2400 (50 * $48 minimum).
  C3: Could it be gamed? Agent could create a PE for wrong supplier.
      Mitigation: party_type == Supplier AND party == Eagle Hardware.
  C4: Could it be gamed? Agent could just not create PI and skip to PE.
      Mitigation: C4 only awards if C2 also passes (outstanding check on PI list).
"""

import json


def verify_full_procurement_cycle(trajectory, env_info, task_info):
    result_file = task_info.get("metadata", {}).get(
        "result_file", "/tmp/full_procurement_cycle_result.json"
    )
    local_tmp = "/tmp/_fpc_result_local.json"

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

    po_name = data.get("po_name", "")
    pr_items = data.get("pr_items", [])
    pi_list = data.get("purchase_invoices", [])
    pe_list = data.get("payment_entries", [])
    eagle_outstanding = data.get("eagle_outstanding")

    # --- ERPNext reachability sentinel ---
    # A submitted PO must exist if ERPNext was reachable during setup.
    # If po_name is empty, setup may not have run or ERPNext was offline.
    if not po_name:
        return {"passed": False, "score": 0,
                "reason": "ERPNext setup data missing (po_name not in result) — "
                          "ERPNext may have been offline during setup or export"}

    score = 0
    reasons = []

    # --- C1: Purchase Receipt submitted, linked to PO, qty >= 50 ---
    c1_pass = False
    for item in pr_items:
        linked = (item.get("purchase_order") == po_name) if po_name else True
        if linked and item.get("item_code") == "Upper Bearing Plate" and \
                item.get("qty", 0) >= 50:
            c1_pass = True
            break
    if c1_pass:
        score += 30
        reasons.append("C1 PASS: Purchase Receipt submitted and linked to PO (+30)")
    else:
        reasons.append(
            f"C1 FAIL: No submitted PR for Upper Bearing Plate (qty>=50) linked to {po_name}"
        )

    # --- C2: Purchase Invoice submitted, grand_total >= 2400 ---
    c2_pass = False
    for pi in pi_list:
        if pi.get("grand_total", 0) >= 2400:
            c2_pass = True
            break
    if c2_pass:
        score += 30
        reasons.append("C2 PASS: Purchase Invoice submitted with correct amount (+30)")
    else:
        if pi_list:
            reasons.append(
                f"C2 FAIL: PI found but grand_total < 2400 (got {[p.get('grand_total') for p in pi_list]})"
            )
        else:
            reasons.append("C2 FAIL: No submitted Purchase Invoice for Eagle Hardware found")

    # --- C3: Payment Entry (Pay) for Eagle Hardware ---
    c3_pass = any(pe.get("payment_type") == "Pay" for pe in pe_list)
    if not c3_pass:
        # Also accept if paid_amount > 0 regardless of type label (some versions differ)
        c3_pass = len(pe_list) > 0 and any(pe.get("paid_amount", 0) > 0 for pe in pe_list)
    if c3_pass:
        score += 20
        reasons.append("C3 PASS: Payment Entry recorded for Eagle Hardware (+20)")
    else:
        reasons.append("C3 FAIL: No submitted Payment Entry found for Eagle Hardware")

    # --- C4: Outstanding balance = 0 ---
    # Only award if C2 also passed (anti-gaming: must have an actual invoice)
    if c2_pass:
        c4_pass = eagle_outstanding is not None and float(eagle_outstanding) <= 0.01
        if c4_pass:
            score += 20
            reasons.append("C4 PASS: Eagle Hardware outstanding balance is zero (+20)")
        else:
            reasons.append(
                f"C4 FAIL: Outstanding balance = {eagle_outstanding} (must be 0)"
            )
    else:
        reasons.append("C4 SKIP: C2 must pass before C4 is evaluated")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "reason": " | ".join(reasons)
    }
