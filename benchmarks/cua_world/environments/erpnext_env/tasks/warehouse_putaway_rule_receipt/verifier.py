#!/usr/bin/env python3
"""
Verifier for warehouse_putaway_rule_receipt task.

Task: Set up Putaway Rules and receive goods using them.
      Rules:
      1) Rotor Blade -> Blade Rack 1, cap 40, prio 1
      2) Rotor Blade -> Blade Rack 2, cap 40, prio 2
      3) Gearbox -> Heavy Parts, cap 50, prio 1
      Process PO of 60 Rotor Blades and 25 Gearboxes. Apply rules so they split.
      
Scoring:
  C1 [30 pts]: 3 Putaway Rules configured with correct Item, Warehouse, Capacity, Priority.
  C2 [20 pts]: PR submitted & linked to PO.
  C3 [15 pts]: Putaway logic applied (apply_putaway_rule=1).
  C4 [35 pts]: Stock Ledger shows 40 Blades in Rack 1, 20 in Rack 2, and 25 Gearboxes in Heavy Parts.

Pass threshold is 70 points.
"""

import json

def verify_warehouse_putaway_rule_receipt(trajectory, env_info, task_info):
    result_file = task_info.get("metadata", {}).get(
        "result_file", "/tmp/warehouse_putaway_rule_receipt_result.json"
    )
    local_tmp = "/tmp/_wprr_result_local.json"

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        copy_from_env(result_file, local_tmp)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result file missing: {e}"}

    try:
        with open(local_tmp) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not parse result JSON: {e}"}

    po_name = data.get("po_name", "")
    putaway_rules = data.get("putaway_rules", [])
    purchase_receipts = data.get("purchase_receipts", [])
    stock_summary = data.get("stock_summary", {})

    if not po_name:
        return {"passed": False, "score": 0, "feedback": "ERPNext setup data missing (po_name empty)."}

    score = 0
    feedback_parts = []

    # C1: Putaway Rules (30 pts)
    # Check if the required rules exist
    rule1_ok = False
    rule2_ok = False
    rule3_ok = False
    
    for r in putaway_rules:
        item = r.get("item_code")
        wh = r.get("warehouse")
        cap = float(r.get("capacity", 0))
        prio = int(r.get("priority", 0))
        
        if item == "Rotor Blade" and wh == "Blade Rack 1 - WP" and cap == 40 and prio == 1:
            rule1_ok = True
        if item == "Rotor Blade" and wh == "Blade Rack 2 - WP" and cap == 40 and prio == 2:
            rule2_ok = True
        if item == "Gearbox" and wh == "Heavy Parts - WP" and cap == 50 and prio == 1:
            rule3_ok = True

    rules_met = sum([rule1_ok, rule2_ok, rule3_ok])
    score += rules_met * 10
    
    if rules_met == 3:
        feedback_parts.append("C1 PASS: All 3 Putaway Rules configured correctly (+30)")
    else:
        feedback_parts.append(f"C1 FAIL: {rules_met}/3 Putaway Rules configured correctly (+{rules_met*10})")

    # C2: PR submitted & linked (20 pts)
    c2_pass = len(purchase_receipts) > 0
    if c2_pass:
        score += 20
        feedback_parts.append("C2 PASS: Purchase Receipt submitted and linked to PO (+20)")
    else:
        feedback_parts.append("C2 FAIL: No submitted Purchase Receipt linked to PO")

    # C3: Putaway logic applied (15 pts)
    c3_pass = any(pr.get("apply_putaway_rule") in [1, True, "1"] for pr in purchase_receipts)
    if c3_pass:
        score += 15
        feedback_parts.append("C3 PASS: 'Apply Putaway Rule' was checked on the Purchase Receipt (+15)")
    else:
        feedback_parts.append("C3 FAIL: 'Apply Putaway Rule' not checked on Purchase Receipt")

    # C4: Stock correctly split (35 pts)
    # Target: 40 in Blade Rack 1, 20 in Blade Rack 2, 25 in Heavy Parts
    br1_qty = float(stock_summary.get("Blade Rack 1 - WP", 0))
    br2_qty = float(stock_summary.get("Blade Rack 2 - WP", 0))
    hp_qty = float(stock_summary.get("Heavy Parts - WP", 0))

    c4_pass = (br1_qty == 40) and (br2_qty == 20) and (hp_qty == 25)
    
    if c4_pass:
        score += 35
        feedback_parts.append("C4 PASS: Stock split correctly (40, 20, 25) (+35)")
    else:
        # Partial points if at least they got something in the racks
        if br1_qty > 0 or br2_qty > 0 or hp_qty > 0:
            score += 10
            feedback_parts.append(f"C4 PARTIAL: Stock not perfectly split. Got Rack 1: {br1_qty}, Rack 2: {br2_qty}, Heavy Parts: {hp_qty} (+10)")
        else:
            feedback_parts.append(f"C4 FAIL: Stock not split into target racks. Got Rack 1: {br1_qty}, Rack 2: {br2_qty}, Heavy Parts: {hp_qty}")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }