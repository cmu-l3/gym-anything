#!/usr/bin/env python3
"""
Verifier for fleet_delivery_trip_and_fuel_log task.

Task: Combine two specific Delivery Notes into a Delivery Trip for 'Alex Driver'
      and 'WP-TRK-01'. Then create a Vehicle Log for 'WP-TRK-01' recording 15120
      odometer and $60 in fuel expenses.

Scoring (100 pts total, pass >= 80):
  C1 [20 pts] — A submitted Delivery Trip exists.
  C2 [20 pts] — The Delivery Trip is assigned to driver 'Alex Driver' and vehicle 'WP-TRK-01'.
  C3 [20 pts] — Both target Delivery Notes are included in the Delivery Trip's stops.
  C4 [20 pts] — A submitted Vehicle Log exists for 'WP-TRK-01'.
  C5 [20 pts] — The Vehicle Log has odometer = 15120 and fuel expenses totaling ~$60.00.

Anti-Gaming / Robustness Checks:
  - Both documents MUST be fully submitted (`docstatus` == 1), checked by the API query in export.
  - Matches precise auto-generated Delivery Note IDs to prevent gaming with empty/fake documents.
"""

import json

def verify_fleet_delivery_and_log(trajectory, env_info, task_info):
    result_file = task_info.get("metadata", {}).get(
        "result_file", "/tmp/fleet_delivery_result.json"
    )
    local_tmp = "/tmp/_fleet_result_local.json"

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verifier error: copy_from_env not available."}

    try:
        copy_from_env(result_file, local_tmp)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Export file missing or failed: {e}"}

    try:
        with open(local_tmp, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not parse export JSON: {e}"}

    target_driver = data.get("target_driver", "Alex Driver")
    target_vehicle = data.get("target_vehicle", "WP-TRK-01")
    target_dns = data.get("target_delivery_notes", [])
    delivery_trips = data.get("delivery_trips", [])
    vehicle_logs = data.get("vehicle_logs", [])

    if not target_dns:
        return {"passed": False, "score": 0, "feedback": "Setup failure: No target Delivery Notes found in baseline."}

    score = 0
    feedback_parts = []

    # --- C1: Submitted Delivery Trip exists ---
    c1_pass = len(delivery_trips) > 0
    if c1_pass:
        score += 20
        feedback_parts.append("C1 PASS: Submitted Delivery Trip exists (+20)")
    else:
        feedback_parts.append("C1 FAIL: No submitted Delivery Trip found")

    # --- C2: Driver & Vehicle assigned correctly ---
    c2_pass = False
    best_dt = None
    if c1_pass:
        for dt in delivery_trips:
            if dt.get("driver") == target_driver and dt.get("vehicle") == target_vehicle:
                c2_pass = True
                best_dt = dt
                break
            
        if c2_pass:
            score += 20
            feedback_parts.append("C2 PASS: Delivery Trip properly linked to correct Driver & Vehicle (+20)")
        else:
            feedback_parts.append("C2 FAIL: Delivery Trip found, but Driver or Vehicle assignment is incorrect")
    else:
        feedback_parts.append("C2 SKIP: No Delivery Trip to check")

    # --- C3: Both Delivery Notes present in stops ---
    c3_pass = False
    if c1_pass:
        # Check the best DT if C2 passed, or any DT if they messed up C2
        trips_to_check = [best_dt] if best_dt else delivery_trips
        for dt in trips_to_check:
            stops = dt.get("stops", [])
            has_all_dns = all(dn in stops for dn in target_dns)
            if has_all_dns:
                c3_pass = True
                break
        
        if c3_pass:
            score += 20
            feedback_parts.append("C3 PASS: Both Delivery Notes successfully routed in the Delivery Trip (+20)")
        else:
            feedback_parts.append("C3 FAIL: Delivery Trip does not contain both of the required Delivery Notes")
    else:
        feedback_parts.append("C3 SKIP: No Delivery Trip to check")

    # --- C4: Submitted Vehicle Log exists ---
    c4_pass = len(vehicle_logs) > 0
    if c4_pass:
        score += 20
        feedback_parts.append("C4 PASS: Submitted Vehicle Log exists for the vehicle (+20)")
    else:
        feedback_parts.append("C4 FAIL: No submitted Vehicle Log found for vehicle 'WP-TRK-01'")

    # --- C5: Odometer & Fuel metrics ---
    c5_pass = False
    if c4_pass:
        for vl in vehicle_logs:
            odometer_match = (vl.get("odometer") == 15120)
            
            # Check various ways fuel cost could be entered
            fuel_cost_computed = vl.get("computed_fuel_cost", 0)
            alt_amount = vl.get("alt_amount", 0)
            expenses = vl.get("total_expenses", 0)
            
            fuel_match = any(abs(val - 60.0) <= 1.0 for val in [fuel_cost_computed, alt_amount, expenses])
            
            if odometer_match and fuel_match:
                c5_pass = True
                break
                
        if c5_pass:
            score += 20
            feedback_parts.append("C5 PASS: Vehicle Log contains correct 15120 odometer reading and $60.00 expense (+20)")
        else:
            feedback_parts.append("C5 FAIL: Vehicle Log exists, but odometer is not 15120 or fuel expense does not equal $60.00")
    else:
        feedback_parts.append("C5 SKIP: No Vehicle Log to check")

    # Requirements to officially pass the task
    passed = (score >= 80) and c3_pass and c5_pass

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }