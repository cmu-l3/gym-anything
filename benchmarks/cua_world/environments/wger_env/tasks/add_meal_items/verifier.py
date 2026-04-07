#!/usr/bin/env python3
"""
Verifier for add_meal_items task.

VERIFICATION STRATEGY:
1. Programmatic Database Verification:
   - Check if exact 3 items exist in the 'Lunch' meal.
   - Check if specific ingredient IDs (Chicken, Rice, Broccoli) are linked.
   - Check if the gram amounts match expected values (within 5g tolerance).
2. Trajectory Verification (VLM):
   - Confirms the agent used the UI properly to perform these actions.
"""

import os
import json
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_meal_items(traj, env_info, task_info):
    """
    Verify that the user successfully added three specific ingredients 
    with correct amounts to the targeted meal.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    tolerance = metadata.get('amount_tolerance_grams', 5)
    
    score = 0
    feedback_parts = []

    # ================================================================
    # Read result data from the environment
    # ================================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    setup_info = result.get('setup_info', {})
    exported_items = result.get('exported_items', [])
    
    if result.get('export_error'):
        feedback_parts.append(f"Export Error: {result.get('export_error')}")

    # ================================================================
    # Determine Expected Values
    # ================================================================
    chicken_id = setup_info.get('CHICKEN_ID', -1)
    rice_id = setup_info.get('RICE_ID', -1)
    broccoli_id = setup_info.get('BROCCOLI_ID', -1)
    
    expected_items = {
        chicken_id: {"name": "Chicken Breast", "target_amount": 200},
        rice_id: {"name": "Brown Rice", "target_amount": 150},
        broccoli_id: {"name": "Broccoli", "target_amount": 100}
    }

    if chicken_id == -1 or rice_id == -1 or broccoli_id == -1:
        return {"passed": False, "score": 0, "feedback": "Failed to map ingredient IDs from setup."}

    # ================================================================
    # Verification Logic
    # ================================================================
    matched_ingredients = set()
    
    # 1. Check ingredients and amounts
    for item in exported_items:
        ing_id = item.get('ingredient_id')
        amount = item.get('amount', 0)
        
        if ing_id in expected_items:
            expected = expected_items[ing_id]
            matched_ingredients.add(ing_id)
            
            # Score ingredient matching
            score += 15
            feedback_parts.append(f"✅ Found {expected['name']}")
            
            # Score amount accuracy
            if abs(amount - expected['target_amount']) <= tolerance:
                score += 10
                feedback_parts.append(f"✅ {expected['name']} amount correct ({amount}g)")
            else:
                feedback_parts.append(f"❌ {expected['name']} amount incorrect (got {amount}g, expected {expected['target_amount']}g)")
        else:
            feedback_parts.append(f"⚠️ Found unexpected ingredient ID {ing_id}")

    # 2. Check total item count (No extras / missing)
    if len(matched_ingredients) == 3:
        score += 5
        feedback_parts.append("✅ All 3 requested ingredients added")
        
    if len(exported_items) == 3:
        score += 5
        feedback_parts.append("✅ Meal contains exactly 3 items (no duplicates/extras)")
    elif len(exported_items) > 3:
        feedback_parts.append(f"❌ Meal contains {len(exported_items)} items, expected exactly 3")

    # ================================================================
    # VLM Trajectory Verification
    # ================================================================
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        if frames and final:
            prompt = (
                "You are reviewing a user's interaction with a web application (wger fitness tracker). "
                "Did the user use the interface to search for and add food items (Chicken, Rice, Broccoli) "
                "to a nutrition plan? Respond with a JSON object containing:\n"
                "- 'interface_used': true/false\n"
                "- 'reason': brief explanation"
            )
            vlm_response = query_vlm(images=frames + [final], prompt=prompt)
            
            if vlm_response.get("success") and vlm_response.get("parsed", {}).get("interface_used", False):
                score += 15
                feedback_parts.append("✅ VLM verified UI interaction")
            else:
                feedback_parts.append("❌ VLM could not verify proper UI interaction")
    else:
        # If VLM is not available, we give the points if the programmatic check passes perfectly
        if score == 85:
            score += 15
            feedback_parts.append("✅ VLM unavailable, awarding UI points implicitly")

    # ================================================================
    # Final Decision
    # ================================================================
    # Passing requires finding at least 2 of the 3 ingredients and having a generally correct state
    passed = score >= 60 and len(matched_ingredients) >= 2
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }