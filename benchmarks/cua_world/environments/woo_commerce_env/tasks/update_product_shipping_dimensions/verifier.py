#!/usr/bin/env python3
"""
Verifier for update_product_shipping_dimensions task.

Scores based on database state of 3 specific products.
Total Points: 100
- 30 pts per product (10 weight + 10 dims + 10 data entry accuracy)
- 10 pts for global task completion (all products modified)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_shipping(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Define Expectations (Source of Truth)
    # Note: We treat numbers as strings for comparison to avoid float issues, 
    # but normalize "18.50" == "18.5"
    targets = {
        "Oak Coffee Table": {
            "weight": 18.5, "length": 110.0, "width": 60.0, "height": 45.0
        },
        "Ceramic Vase": {
            "weight": 1.2, "length": 15.0, "width": 15.0, "height": 35.0
        },
        "Linen Curtains": {
            "weight": 0.8, "length": 40.0, "width": 30.0, "height": 5.0
        }
    }

    score = 0
    max_score = 100
    feedback = []
    
    products_data = result.get("products", {})
    all_products_processed = True

    for name, target in targets.items():
        p_data = products_data.get(name, {})
        
        if not p_data.get("found", False):
            feedback.append(f"❌ {name}: Product not found in DB.")
            all_products_processed = False
            continue

        # Check modifications (anti-gaming: timestamp check not strictly needed if values match, 
        # but useful to ensure agent actually touched it if values happened to be default - 
        # though setup clears them, so correct values implies action).
        
        # Helper for loose float comparison
        def check_val(key, val_str, expected_float):
            try:
                # Handle empty strings
                if not val_str or val_str.strip() == "":
                    return False
                val_float = float(val_str)
                # Tolerance 0.1
                return abs(val_float - expected_float) < 0.1
            except ValueError:
                return False

        # Evaluate Weight (10 pts)
        w_correct = check_val("weight", p_data.get("weight"), target["weight"])
        if w_correct:
            score += 10
        else:
            feedback.append(f"❌ {name}: Weight incorrect (Expected {target['weight']}, Got '{p_data.get('weight')}')")

        # Evaluate Dimensions (20 pts total split)
        l_correct = check_val("length", p_data.get("length"), target["length"])
        w_dim_correct = check_val("width", p_data.get("width"), target["width"])
        h_correct = check_val("height", p_data.get("height"), target["height"])

        if l_correct and w_dim_correct and h_correct:
            score += 20
        else:
            # Partial credit for dimensions? Let's keep it strict for simplicity or split it.
            # Splitting: 6 pts each approx
            dims_score = 0
            if l_correct: dims_score += 6
            if w_dim_correct: dims_score += 7
            if h_correct: dims_score += 7
            score += dims_score
            feedback.append(f"❌ {name}: Dimensions mismatch.")

        if not (w_correct and l_correct and w_dim_correct and h_correct):
            all_products_processed = False
        else:
            feedback.append(f"✅ {name}: updated successfully.")

    # Bonus/Completion (10 pts)
    if all_products_processed:
        score += 10
        feedback.append("✅ All products processed correctly.")

    # 3. Final Assessment
    passed = (score >= 90) # Allow minor tolerance but generally strict
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }