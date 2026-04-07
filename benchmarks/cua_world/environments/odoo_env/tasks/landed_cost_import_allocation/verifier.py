#!/usr/bin/env python3
import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_landed_cost_allocation(traj, env_info, task_info):
    """
    Verifies the Landed Cost Allocation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Record Exists (5 pts)
    if result.get("found_record"):
        score += 5
        feedback.append("Landed cost record found.")
    else:
        return {"passed": False, "score": 0, "feedback": "No Landed Cost record found linked to the shipment."}

    # 2. Picking Match (15 pts)
    # Already checked in export script to select candidate, but worth explicit points
    if result.get("picking_match"):
        score += 15
        feedback.append("Correct shipment (Picking) linked.")

    # 3. Validated/Done State (30 pts)
    if result.get("state") == 'done':
        score += 30
        feedback.append("Record is validated.")
    else:
        feedback.append(f"Record state is '{result.get('state')}' (expected 'done').")

    # 4. Total Amount (20 pts)
    # Target: 4800.00
    total = result.get("total_amount", 0)
    if abs(total - 4800.0) < 1.0:
        score += 20
        feedback.append("Total amount correct ($4,800).")
    else:
        feedback.append(f"Total amount incorrect: ${total} (expected $4,800).")

    # 5. Cost Lines Check (30 pts)
    # Need 3 lines: Freight (2400), Duty (1800), Insurance (600)
    # All must use 'by_current_cost'
    lines = result.get("lines", [])
    
    if len(lines) == 3:
        score += 5
        feedback.append("Correct number of cost lines (3).")
    else:
        feedback.append(f"Incorrect number of cost lines: {len(lines)}.")

    # Check split methods and amounts
    split_method_correct = 0
    amounts_matched = 0
    
    # We look for fuzzy matches on amounts since names might vary (user types them)
    targets = [2400.0, 1800.0, 600.0]
    matched_targets = []

    for line in lines:
        # Check split method
        if line.get('split_method') == 'by_current_cost':
            split_method_correct += 1
        
        # Check amount
        amt = line.get('price_unit', 0)
        # Find closest target that hasn't been matched
        best_target = None
        for t in targets:
            if t not in matched_targets and abs(amt - t) < 1.0:
                best_target = t
                break
        
        if best_target:
            amounts_matched += 1
            matched_targets.append(best_target)

    # Score Split Methods (max 15)
    if split_method_correct == 3:
        score += 15
        feedback.append("Split method correct for all lines.")
    elif split_method_correct > 0:
        score += (split_method_correct * 5)
        feedback.append(f"Split method correct for {split_method_correct}/3 lines.")
    else:
        feedback.append("Split method incorrect (expected 'By Current Cost').")

    # Score Individual Amounts (max 10, remaining from Total Amount check logic covering global correctness)
    # Actually, let's just add bonus if specific breakdown is right
    if amounts_matched == 3:
        score += 10
        feedback.append("Individual cost line amounts correct.")
    else:
        feedback.append(f"Only {amounts_matched}/3 specific cost amounts matched.")

    # Cap score at 100
    if score > 100: score = 100

    passed = (score >= 70) and (result.get("state") == 'done')

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }