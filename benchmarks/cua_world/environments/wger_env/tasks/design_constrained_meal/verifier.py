#!/usr/bin/env python3
"""
Verifier for design_constrained_meal task.

Evaluates if the agent successfully used the application to satisfy mathematical
macronutrient constraints in a newly created meal.

Checks:
1. Meal created with correct name and plan
2. Meal has items
3. Protein constraint satisfied (>= 30g)
4. Carb constraint satisfied (< 10g)
5. Anti-gaming check (Meal was created during task)
6. VLM Trajectory Verification (Agent used UI)
"""

import os
import json
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are verifying an agent's trajectory in a fitness web application.
The goal of the agent was to create a new nutrition meal called 'Keto Breakfast' and add specific gram amounts of ingredients to meet specific macronutrient goals (high protein, low carb).

Please look at the trajectory frames and final screenshot to confirm:
1. Did the agent navigate the nutrition section of the app?
2. Did the agent interact with ingredient search/amount forms?

Respond ONLY with a JSON dictionary in this exact format:
{
    "used_nutrition_ui": true/false,
    "interacted_with_ingredients": true/false,
    "reasoning": "brief explanation"
}"""


def verify_design_constrained_meal(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available."}

    metadata = task_info.get('metadata', {})
    min_protein = metadata.get('min_protein_g', 30.0)
    max_carbs = metadata.get('max_carbs_g', 10.0)

    # 1. Retrieve the task result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    db_eval = result.get('db_eval', {})
    initial_meal_id = result.get('initial_meal_id', 0)
    
    score = 0
    feedback_parts = []
    
    # Criteria evaluation
    meal_exists = db_eval.get('meal_exists', False)
    has_items = db_eval.get('has_items', False)
    protein = db_eval.get('protein_g', 0.0)
    carbs = db_eval.get('carbs_g', 0.0)
    meal_id = db_eval.get('meal_id', 0)
    
    # 1. Meal Exists (20 pts)
    if meal_exists:
        score += 20
        feedback_parts.append("Keto Breakfast meal created.")
    else:
        feedback_parts.append("Keto Breakfast meal missing.")
        
    # 2. Has Items (20 pts)
    if has_items:
        score += 20
        feedback_parts.append(f"Meal has {db_eval.get('items_count')} items.")
    else:
        feedback_parts.append("Meal has zero ingredients.")

    # 3. Protein Constraint (25 pts)
    protein_passed = False
    if has_items and protein >= min_protein:
        score += 25
        protein_passed = True
        feedback_parts.append(f"Protein sufficient ({protein}g >= {min_protein}g).")
    elif has_items:
        feedback_parts.append(f"Protein failed ({protein}g < {min_protein}g).")

    # 4. Carbohydrate Constraint (25 pts)
    carbs_passed = False
    if has_items and carbs < max_carbs:
        score += 25
        carbs_passed = True
        feedback_parts.append(f"Carbs restricted ({carbs}g < {max_carbs}g).")
    elif has_items:
        feedback_parts.append(f"Carbs failed ({carbs}g >= {max_carbs}g).")

    # 5. Anti-gaming (Meal created during task)
    created_during_task = False
    if meal_exists and meal_id > initial_meal_id:
        created_during_task = True
        feedback_parts.append("Meal newly created (anti-gaming passed).")
    elif meal_exists:
        feedback_parts.append("Meal ID <= initial max. Reused old meal.")

    # 6. VLM Verification (10 pts)
    vlm_passed = False
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            images = frames + [final_frame] if final_frame else frames
            
            if images:
                vlm_resp = query_vlm(prompt=VERIFICATION_PROMPT, images=images)
                if vlm_resp and vlm_resp.get("success"):
                    parsed = vlm_resp.get("parsed", {})
                    if parsed.get("used_nutrition_ui") and parsed.get("interacted_with_ingredients"):
                        score += 10
                        vlm_passed = True
                        feedback_parts.append("VLM confirms UI interaction.")
                    else:
                        feedback_parts.append("VLM did not detect nutrition UI usage.")
        except Exception as e:
            logger.warning(f"VLM error: {e}")

    # Pass threshold: 90 points AND strict mathematical constraints satisfied
    constraints_met = protein_passed and carbs_passed
    passed = (score >= 90) and constraints_met and created_during_task

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "protein": protein,
            "carbs": carbs,
            "items_count": db_eval.get('items_count', 0),
            "vlm_passed": vlm_passed
        }
    }