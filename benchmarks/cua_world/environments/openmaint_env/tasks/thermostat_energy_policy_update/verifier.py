#!/usr/bin/env python3
import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_thermostat_energy_policy_update(traj, env_info, task_info):
    """
    Verifies that the agent correctly updated thermostat records based on the policy.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            local_path = tmp.name
        copy_from_env("/tmp/task_result.json", local_path)
        with open(local_path) as f:
            data = json.load(f)
        os.unlink(local_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}

    if "error" in data:
        return {"passed": False, "score": 0, "feedback": f"Export error: {data['error']}"}

    results = data.get("results", {})
    baseline = data.get("baseline", {})
    
    hq_id = baseline.get("hq_id")
    wh_id = baseline.get("wh_id")

    # Metrics
    score = 0
    feedback = []
    
    # Categories
    smart_hq_total = 0
    smart_hq_correct = 0
    
    manual_hq_total = 0
    manual_hq_correct = 0
    
    contamination_total = 0
    contamination_failures = 0

    do_nothing = True

    for code, info in results.items():
        actual_notes = info.get("actual_notes", "").lower()
        bld_id = info.get("building_id")
        is_smart = info.get("is_smart")

        if actual_notes.strip():
            do_nothing = False

        # Check Scope: HQ
        if bld_id == hq_id:
            if is_smart:
                smart_hq_total += 1
                if "eco-2026" in actual_notes:
                    smart_hq_correct += 1
                else:
                    feedback.append(f"[{code}] Missing 'Eco-2026' profile in Smart HQ thermostat.")
            else:
                manual_hq_total += 1
                if "replace" in actual_notes:
                    manual_hq_correct += 1
                else:
                    feedback.append(f"[{code}] Missing 'Replace' action in Manual HQ thermostat.")
        
        # Check Scope: Warehouse (Contamination)
        elif bld_id == wh_id:
            contamination_total += 1
            if "eco-2026" in actual_notes or "replace" in actual_notes:
                contamination_failures += 1
                feedback.append(f"[{code}] WRONG: Modified thermostat in Warehouse (Out of Scope).")

    if do_nothing:
        return {"passed": False, "score": 0, "feedback": "No changes detected in any records."}

    # Scoring
    # C1: Smart HQ Updates (35 pts)
    c1_score = 0
    if smart_hq_total > 0:
        c1_score = (smart_hq_correct / smart_hq_total) * 35
    
    # C2: Manual HQ Updates (35 pts)
    c2_score = 0
    if manual_hq_total > 0:
        c2_score = (manual_hq_correct / manual_hq_total) * 35
        
    # C3: Scope Control (30 pts)
    # Deduct points for contamination
    c3_score = 30
    if contamination_failures > 0:
        # Severe penalty for scope violation, but floor at 0
        penalty = (contamination_failures / contamination_total) * 30
        c3_score = max(0, 30 - penalty)

    total_score = c1_score + c2_score + c3_score
    
    passed = total_score >= 70

    if not feedback:
        feedback.append("All records updated correctly.")

    return {
        "passed": passed,
        "score": round(total_score, 1),
        "feedback": " ".join(feedback),
        "details": {
            "smart_hq_correct": f"{smart_hq_correct}/{smart_hq_total}",
            "manual_hq_correct": f"{manual_hq_correct}/{manual_hq_total}",
            "contamination_failures": f"{contamination_failures}/{contamination_total}"
        }
    }