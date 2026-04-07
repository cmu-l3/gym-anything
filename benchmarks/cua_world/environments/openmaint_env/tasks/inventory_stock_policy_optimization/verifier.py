#!/usr/bin/env python3
import json
import logging
import re
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_inventory_stock_policy_optimization(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Updated Min/Max thresholds for active parts correctly.
    2. Set the obsolete part to inactive AND did not update its thresholds.
    3. Created a Work Order with the correct parts and quantities.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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

    parts_state = result.get("parts_state", {})
    work_orders = result.get("work_orders", [])
    
    score = 0
    feedback = []

    # --- Criterion 1: Threshold Updates (25 pts) ---
    # Expected: 
    # SP-BELT-V46: Min 5, Max 20
    # SP-FILT-2020: Min 10, Max 30
    # SP-SENS-T10: Min 5, Max 15
    # SP-VALVE-05: Min 2, Max 5
    
    expected_active = {
        "SP-BELT-V46": (5, 20),
        "SP-FILT-2020": (10, 30),
        "SP-SENS-T10": (5, 15),
        "SP-VALVE-05": (2, 5)
    }
    
    correct_thresholds = 0
    for code, (exp_min, exp_max) in expected_active.items():
        state = parts_state.get(code, {})
        act_min = state.get("min")
        act_max = state.get("max")
        
        # Loose type checking (string vs int)
        try:
            val_min = float(act_min) if act_min is not None else -1
            val_max = float(act_max) if act_max is not None else -1
            if val_min == exp_min and val_max == exp_max:
                correct_thresholds += 1
            else:
                feedback.append(f"{code}: Expected Min/Max {exp_min}/{exp_max}, got {act_min}/{act_max}")
        except:
            feedback.append(f"{code}: Invalid threshold values")

    score_c1 = (correct_thresholds / 4) * 25
    score += score_c1

    # --- Criterion 2 & 3: Obsolete Handling (15 pts + 10 pts) ---
    # SP-FUSE-OLD should be Inactive and retain Old Min/Max (5, 10)
    obs_part = parts_state.get("SP-FUSE-OLD", {})
    is_inactive = (obs_part.get("is_active") is False) or ("inactive" in str(obs_part.get("status", "")).lower()) or ("disposed" in str(obs_part.get("status", "")).lower())
    
    if is_inactive:
        score += 15
    else:
        feedback.append("SP-FUSE-OLD not marked as inactive/obsolete")

    # Anti-gaming: Check if thresholds were preserved
    # Old: Min 5, Max 10. New Policy said 0, 0 but Status=Obsolete implies NO UPDATE to logic usually, 
    # but the prompt specifically said "do NOT update the stock thresholds".
    # So we expect 5 and 10.
    obs_min = obs_part.get("min")
    obs_max = obs_part.get("max")
    try:
        if float(obs_min) == 5 and float(obs_max) == 10:
            score += 10
        else:
            feedback.append(f"SP-FUSE-OLD thresholds changed to {obs_min}/{obs_max} (should be preserved)")
    except:
        feedback.append("SP-FUSE-OLD thresholds invalid")

    # --- Criterion 4, 5, 6: Work Order (50 pts total) ---
    # WO Creation (10 pts)
    # Order Accuracy Items (20 pts)
    # Order Accuracy Qty (20 pts)
    
    found_wo = False
    wo_score = 0
    
    if work_orders:
        found_wo = True
        score += 10 # WO created with correct keywords
        
        # Analyze the best matching WO
        target_wo = work_orders[0] # Take the first one found by export script
        
        full_text = (target_wo.get("description", "") + " " + target_wo.get("notes", "")).lower()
        
        # Expected Logic:
        # SP-BELT-V46: Cur 2, NewMin 5 -> Order 20 - 2 = 18
        # SP-SENS-T10: Cur 4, NewMin 5 -> Order 15 - 4 = 11
        # SP-VALVE-05: Cur 0, NewMin 2 -> Order 5 - 0 = 5
        # SP-FILT-2020: Cur 15, NewMin 10 -> No Order
        
        expected_items = {
            "SP-BELT-V46": 18,
            "SP-SENS-T10": 11,
            "SP-VALVE-05": 5
        }
        forbidden_items = ["SP-FILT-2020", "SP-FUSE-OLD"]
        
        # Check Items Existence
        items_hit = 0
        items_false_positive = 0
        
        for item in expected_items:
            # Match loose patterns like "SP-BELT-V46" or "V-Belt"
            if item.lower() in full_text or item.split("-")[1].lower() in full_text:
                items_hit += 1
            else:
                feedback.append(f"WO missing required item: {item}")
                
        for item in forbidden_items:
            if item.lower() in full_text:
                items_false_positive += 1
                feedback.append(f"WO contains unneeded item: {item}")
        
        # Score Items (20 pts)
        # 3 required, max 20 pts -> ~6.6 per item
        # Penalize false positives
        item_score = (items_hit / 3) * 20
        item_score -= (items_false_positive * 5)
        item_score = max(0, item_score)
        score += item_score
        
        # Check Quantities (20 pts)
        # Look for numbers near the item names or just numbers in text matching expectations
        qty_hit = 0
        
        # Simple heuristic: are the specific numbers 18, 11, and 5 present in text?
        # A more robust check would pair them, but simple existence is a good proxy for effort here
        for qty in [18, 11, 5]:
            if str(qty) in full_text:
                qty_hit += 1
            else:
                feedback.append(f"WO missing calculated quantity: {qty}")
        
        qty_score = (qty_hit / 3) * 20
        score += qty_score
        
    else:
        feedback.append("No suitable Procurement Work Order found")

    return {
        "passed": score >= 65,
        "score": round(score),
        "feedback": "; ".join(feedback)
    }