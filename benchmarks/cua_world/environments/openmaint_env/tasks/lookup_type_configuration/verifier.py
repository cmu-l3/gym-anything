#!/usr/bin/env python3
"""Verifier for lookup_type_configuration task.

Scoring breakdown (100 points total):
  C1 (25 pts): MaintenanceShift exists + 4 correct values
  C2 (25 pts): CostCenter exists + 5 correct values
  C3 (25 pts): FailureCategory exists + 6 correct values
  C4 (10 pts): Value ordering matches requirements
  C5 (15 pts): Preservation of existing lookup types

Pass threshold: score >= 60
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_lookup_type_configuration(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Expected values from metadata
    metadata = task_info.get("metadata", {})
    expected_data = metadata.get("expected_lookups", {})
    
    # Retrieve result JSON
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            local_path = tmp.name
        copy_from_env("/tmp/lookup_result.json", local_path)
        with open(local_path) as f:
            result = json.load(f)
        os.unlink(local_path)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve result file: {e}"
        }

    if result.get("error"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Export error: {result['error']}"
        }

    targets = result.get("targets", {})
    preservation = result.get("preservation", {})
    baseline = result.get("baseline", {})
    
    score = 0
    feedback_parts = []
    
    # Do-nothing check
    if not any(t.get("exists") for t in targets.values()):
        return {
            "passed": False,
            "score": 0,
            "feedback": "DO-NOTHING: No target lookup types were created."
        }

    # Helper to verify values
    def check_values(actual_list, expected_list):
        # 1. Check if all expected codes exist
        # 2. Check if descriptions match (loose match)
        # 3. Check ordering
        
        matches = 0
        descriptions_ok = 0
        order_ok = 0
        
        # Map actual codes to their objects/indices
        actual_map = {item['code'].upper(): item for i, item in enumerate(actual_list)}
        actual_ordered = [item['code'].upper() for item in actual_list]
        
        for i, exp in enumerate(expected_list):
            exp_code = exp['code'].upper()
            if exp_code in actual_map:
                matches += 1
                act_item = actual_map[exp_code]
                
                # Description check
                if exp['desc'].lower() in act_item['description'].lower() or \
                   act_item['description'].lower() in exp['desc'].lower():
                    descriptions_ok += 1
                
                # Order check: Is it in the same relative position?
                # Strict check: index matches
                # Lenient check: just needs to be in list.
                # Requirement said "listed order".
                if i < len(actual_ordered) and actual_ordered[i] == exp_code:
                    order_ok += 1
            else:
                pass
                
        return matches, descriptions_ok, order_ok

    # C1: MaintenanceShift (25 pts)
    ms_target = targets.get("MaintenanceShift", {})
    if ms_target.get("exists"):
        matches, descs, orders = check_values(ms_target.get("values", []), expected_data["MaintenanceShift"])
        # Partial scoring: 10 pts for existence, 15 pts for values
        ms_score = 10
        if matches == 4:
            ms_score += 10
            if descs >= 3: # Allow small typos
                ms_score += 5
        elif matches >= 2:
            ms_score += 5
        
        score += ms_score
        feedback_parts.append(f"MaintenanceShift: Exists, {matches}/4 values correct ({ms_score}/25)")
    else:
        feedback_parts.append("MaintenanceShift: Missing (0/25)")
        matches, orders = 0, 0 # for later use

    # C2: CostCenter (25 pts)
    cc_target = targets.get("CostCenter", {})
    if cc_target.get("exists"):
        matches_cc, descs_cc, orders_cc = check_values(cc_target.get("values", []), expected_data["CostCenter"])
        cc_score = 10
        if matches_cc == 5:
            cc_score += 10
            if descs_cc >= 4:
                cc_score += 5
        elif matches_cc >= 3:
            cc_score += 5
            
        score += cc_score
        feedback_parts.append(f"CostCenter: Exists, {matches_cc}/5 values correct ({cc_score}/25)")
    else:
        feedback_parts.append("CostCenter: Missing (0/25)")
        matches_cc, orders_cc = 0, 0

    # C3: FailureCategory (25 pts)
    fc_target = targets.get("FailureCategory", {})
    if fc_target.get("exists"):
        matches_fc, descs_fc, orders_fc = check_values(fc_target.get("values", []), expected_data["FailureCategory"])
        fc_score = 10
        if matches_fc == 6:
            fc_score += 10
            if descs_fc >= 5:
                fc_score += 5
        elif matches_fc >= 3:
            fc_score += 5
            
        score += fc_score
        feedback_parts.append(f"FailureCategory: Exists, {matches_fc}/6 values correct ({fc_score}/25)")
    else:
        feedback_parts.append("FailureCategory: Missing (0/25)")
        matches_fc, orders_fc = 0, 0

    # C4: Ordering (10 pts)
    # Total possible ordered items = 4+5+6 = 15
    total_ordered = orders + orders_cc + orders_fc
    if total_ordered >= 14:
        score += 10
        feedback_parts.append("Ordering: Perfect/Near Perfect (10/10)")
    elif total_ordered >= 10:
        score += 5
        feedback_parts.append("Ordering: Mostly Correct (5/10)")
    else:
        feedback_parts.append(f"Ordering: Incorrect ({total_ordered}/15 correct positions) (0/10)")

    # C5: Preservation (15 pts)
    prio_match = preservation.get("priority_values_match", False)
    total_curr = preservation.get("total_current", 0)
    total_base = preservation.get("total_baseline", 0)
    
    # We expect total_curr to be total_base + 3 (created types)
    # Allow some flexibility if they created extra types or deleted non-critical ones? No, "Do not delete"
    
    preservation_ok = True
    if not prio_match:
        preservation_ok = False
        feedback_parts.append("Preservation: Priority lookup modified")
    
    # If they deleted old ones, current < baseline + created (assuming they created some)
    # Simple check: current >= baseline
    if total_curr < total_base:
        preservation_ok = False
        feedback_parts.append("Preservation: Lookup types detected missing")

    if preservation_ok:
        score += 15
        feedback_parts.append("Preservation: OK (15/15)")
    else:
        feedback_parts.append("Preservation: Failed (0/15)")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }