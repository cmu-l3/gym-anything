#!/usr/bin/env python3
import json
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def clean_cost(val):
    if not val: 
        return 0.0
    val_str = str(val).replace('$', '').replace(',', '').strip()
    try:
        return float(val_str)
    except ValueError:
        return 0.0

def verify_accessory_provisioning(traj, env_info, task_info):
    """
    Verifies that the agent created 5 expected accessories with precise details 
    and checked them out correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy_from_env unavailable."}

    # Retrieve expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_category = metadata.get('expected_category', "Computer Peripherals")
    expected_users = metadata.get('expected_users', ["msantos", "jliu", "apatel"])
    expected_accessories = metadata.get('expected_accessories', [])

    if not expected_accessories:
        return {"passed": False, "score": 0, "feedback": "Task metadata missing expected accessories."}

    # Fetch result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env('/tmp/task_result.json', temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Variables for scoring
    score = 0
    feedback = []
    
    initial_count = result.get('initial_accessory_count', 0)
    final_count = result.get('final_accessory_count', 0)
    system_accessories = result.get('accessories', [])

    # Anti-gaming: Ensure agent actually added items
    if final_count - initial_count < 1:
        return {"passed": False, "score": 0, "feedback": "No new accessories were created. Do-nothing detected."}

    # Metrics trackers
    c1_found = 0
    c2_qty_correct = 0
    c3_cost_correct = 0
    c4_cat_correct = 0
    c6_min_qty_correct = 0
    c7_model_correct = 0
    total_checkouts_found = 0

    # Process each expected accessory
    for exp in expected_accessories:
        exp_name = exp['name']
        
        # Look for the accessory in the system by exact or partial name match
        matched_acc = None
        for sys_acc in system_accessories:
            if exp_name.lower() in sys_acc['name'].lower():
                matched_acc = sys_acc
                break
        
        if not matched_acc:
            feedback.append(f"Missing accessory: {exp_name}")
            continue
            
        c1_found += 1
        acc_fb = [f"Found '{exp_name}'"]

        # C2: Quantity
        if matched_acc['qty'] == exp['qty']:
            c2_qty_correct += 1
        else:
            acc_fb.append(f"qty={matched_acc['qty']} (exp {exp['qty']})")

        # C3: Cost
        sys_cost = clean_cost(matched_acc['purchase_cost'])
        if math.isclose(sys_cost, exp['purchase_cost'], abs_tol=0.1):
            c3_cost_correct += 1
        else:
            acc_fb.append(f"cost=${sys_cost} (exp ${exp['purchase_cost']})")

        # C4: Category
        if matched_acc['category_name'] == expected_category:
            c4_cat_correct += 1
        else:
            acc_fb.append(f"cat='{matched_acc['category_name']}' (exp '{expected_category}')")

        # C6: Min Qty
        if matched_acc['min_qty'] == exp['min_qty']:
            c6_min_qty_correct += 1
        else:
            acc_fb.append(f"min_qty={matched_acc['min_qty']} (exp {exp['min_qty']})")

        # C7: Model Number
        if str(matched_acc['model_number']).strip() == str(exp['model_number']).strip():
            c7_model_correct += 1
        else:
            acc_fb.append(f"model='{matched_acc['model_number']}' (exp '{exp['model_number']}')")

        # C5: Checkouts (Each expected accessory should be checked out to all 3 users)
        co_list = matched_acc['checked_out_to']
        user_matches = sum(1 for u in expected_users if u in co_list)
        total_checkouts_found += user_matches
        
        if len(acc_fb) > 1:
            feedback.append("; ".join(acc_fb))

    # Calculate Score
    # C1: Names (20 pts)
    if c1_found == 5: score += 20
    elif c1_found >= 3: score += 12
    elif c1_found >= 1: score += 5
    
    # C2: Qty (15 pts)
    if c2_qty_correct == 5: score += 15
    elif c2_qty_correct >= 3: score += 9
    elif c2_qty_correct >= 1: score += 3

    # C3: Cost (10 pts)
    if c3_cost_correct == 5: score += 10
    elif c3_cost_correct >= 3: score += 6
    elif c3_cost_correct >= 1: score += 2

    # C4: Category (10 pts)
    if c4_cat_correct == 5: score += 10
    elif c4_cat_correct >= 3: score += 6
    elif c4_cat_correct >= 1: score += 2

    # C6: Min Qty (10 pts)
    if c6_min_qty_correct == 5: score += 10
    elif c6_min_qty_correct >= 3: score += 6
    elif c6_min_qty_correct >= 1: score += 2

    # C7: Model Number (10 pts)
    if c7_model_correct == 5: score += 10
    elif c7_model_correct >= 3: score += 6
    elif c7_model_correct >= 1: score += 2

    # C5: Checkouts (25 pts)
    if total_checkouts_found == 15: score += 25
    elif total_checkouts_found >= 12: score += 20
    elif total_checkouts_found >= 9: score += 15
    elif total_checkouts_found >= 5: score += 10
    elif total_checkouts_found >= 1: score += 3

    # Status summary
    feedback.insert(0, f"Score Breakdown: Created={c1_found}/5, Qty={c2_qty_correct}/5, Cost={c3_cost_correct}/5, Cat={c4_cat_correct}/5, Checkouts={total_checkouts_found}/15.")

    # Pass logic: Must have overall >=60, created at least 3 correctly, and checked out at least 5
    passed = (score >= 60) and (c1_found >= 3) and (total_checkouts_found >= 5)

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }