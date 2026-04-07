#!/usr/bin/env python3
"""
Verifier for scale_meal_batch_cooking task.
Reads exported database state to strictly verify mathematical precision and non-destructive operations.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_scale_meal_batch_cooking(traj, env_info, task_info):
    """
    Verifies the batch meal was scaled correctly without damaging the original meal.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve expected scaling amounts from metadata
    metadata = task_info.get('metadata', {})
    expected_scaled = metadata.get('expected_scaled_amounts', {
        "quinoa": 1875,
        "salmon": 4500,
        "sweet_potato": 5000,
        "spinach": 2125
    })
    
    expected_original = metadata.get('original_amounts', {
        "quinoa": 75,
        "salmon": 180,
        "sweet_potato": 200,
        "spinach": 85
    })

    # Read exported JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    db_state = result.get('db_state', {})
    if "error" in db_state:
        return {"passed": False, "score": 0, "feedback": f"Database query error: {db_state['error']}"}

    score = 0
    feedback_parts = []
    
    # 1. New Meal Exists & Correct Plan Association (15 + 10 = 25 pts)
    plan_exists = db_state.get('plan_exists', False)
    new_meal = db_state.get('new_meal', {"exists": False, "items": {}})
    
    if not plan_exists:
        return {"passed": False, "score": 0, "feedback": "FAIL: 'University Athlete Menu' plan was deleted!"}
        
    if new_meal.get('exists'):
        score += 25
        feedback_parts.append("New meal 'Performance Bowl (25 Servings)' correctly created")
    else:
        feedback_parts.append("New meal not found (or named incorrectly)")

    # 2. Original Meal Preserved (15 pts)
    original_meal = db_state.get('original_meal', {"exists": False, "items": {}})
    original_preserved = False
    
    if original_meal.get('exists'):
        items = original_meal.get('items', {})
        # Check that original amounts weren't tampered with
        q_ok = any(abs(items[k] - expected_original["quinoa"]) < 0.1 for k in items if 'quinoa' in k.lower())
        sa_ok = any(abs(items[k] - expected_original["salmon"]) < 0.1 for k in items if 'salmon' in k.lower())
        sp_ok = any(abs(items[k] - expected_original["sweet_potato"]) < 0.1 for k in items if 'potato' in k.lower())
        sn_ok = any(abs(items[k] - expected_original["spinach"]) < 0.1 for k in items if 'spinach' in k.lower())
        
        if q_ok and sa_ok and sp_ok and sn_ok and len(items) == 4:
            original_preserved = True
            score += 15
            feedback_parts.append("Original meal safely preserved")
        else:
            feedback_parts.append("Original meal ingredients or amounts were modified")
    else:
        feedback_parts.append("FAIL: Original meal was deleted or renamed")

    # 3. New Meal Item Validations (up to 60 pts)
    scaled_ingredients_correct = 0
    if new_meal.get('exists'):
        items = new_meal.get('items', {})
        
        # Check exactly 4 ingredients (20 pts)
        if len(items) == 4:
            score += 20
            feedback_parts.append("New meal has exactly 4 items")
        else:
            feedback_parts.append(f"New meal has {len(items)} items (expected 4)")
            
        # Helper to flexibly match ingredient keys in dict and check value
        def check_ingredient(keyword, expected_val):
            for k, v in items.items():
                if keyword in k.lower() and abs(v - expected_val) < 0.1:
                    return True
            return False

        # Quinoa scaled correctly (10 pts)
        if check_ingredient('quinoa', expected_scaled['quinoa']):
            score += 10
            scaled_ingredients_correct += 1
            feedback_parts.append("Quinoa scaled perfectly (1875g)")
            
        # Salmon scaled correctly (10 pts)
        if check_ingredient('salmon', expected_scaled['salmon']):
            score += 10
            scaled_ingredients_correct += 1
            feedback_parts.append("Salmon scaled perfectly (4500g)")
            
        # Sweet Potato scaled correctly (10 pts)
        if check_ingredient('potato', expected_scaled['sweet_potato']):
            score += 10
            scaled_ingredients_correct += 1
            feedback_parts.append("Sweet Potato scaled perfectly (5000g)")
            
        # Spinach scaled correctly (10 pts)
        if check_ingredient('spinach', expected_scaled['spinach']):
            score += 10
            scaled_ingredients_correct += 1
            feedback_parts.append("Spinach scaled perfectly (2125g)")

    # Evaluation Rules
    # Pass threshold is 80, original MUST be preserved, and at least 3 scaled ingredients MUST be correct
    passed = False
    if score >= 80 and original_preserved and scaled_ingredients_correct >= 3:
        passed = True

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }