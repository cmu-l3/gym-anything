#!/usr/bin/env python3
"""
Verifier for sync_macros_to_bodyweight task.

Verifies:
1. Dynamic Math: Multiplies the retrieved database weight by the strict ratios.
2. Data Validation: Checks if the updated plan goals match the calculated targets (±1g to account for rounding).
3. Trajectory Verification: Uses VLM to confirm the agent actually navigated the UI.
"""

import os
import json
import logging
import tempfile

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying a fitness tracking workflow.
Look at these screenshots taken during the task execution.

Did the user do BOTH of the following:
1. View a page showing body weight entries / measurements?
2. Open and interact with a Nutrition Plan (specifically looking at or editing macros/goals)?

Respond with a JSON object containing:
{
    "viewed_weight": true/false,
    "edited_nutrition": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}"""

def verify_sync_macros(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    mult_pro = metadata.get('multiplier_protein', 2.5)
    mult_carb = metadata.get('multiplier_carbs', 4.0)
    mult_fat = metadata.get('multiplier_fat', 1.0)
    tolerance = metadata.get('tolerance_grams', 1.0)

    # 1. Retrieve the exported JSON database state
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            db_state = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported state: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Extract Data
    latest_weight = db_state.get('latest_weight', 0.0)
    plan_exists = db_state.get('plan_exists', False)
    actual_pro = db_state.get('goal_protein', 0.0)
    actual_carb = db_state.get('goal_carbs', 0.0)
    actual_fat = db_state.get('goal_fat', 0.0)

    if not plan_exists or latest_weight == 0.0:
        return {"passed": False, "score": 0, "feedback": "Required database records (weight or plan) are missing."}

    # 3. Calculate Targets (Using standard mathematical rounding)
    expected_pro = round(latest_weight * mult_pro)
    expected_carb = round(latest_weight * mult_carb)
    expected_fat = round(latest_weight * mult_fat)

    score = 0
    feedback_parts = [f"Found dynamic weight: {latest_weight}kg."]
    
    # 4. Programmatic Verification (70 Points Total)
    # Check Protein (20 pts)
    if abs(actual_pro - expected_pro) <= tolerance and actual_pro > 0:
        score += 20
        feedback_parts.append(f"✅ Protein Correct ({actual_pro}g matches {expected_pro}g)")
    else:
        feedback_parts.append(f"❌ Protein Incorrect (Expected ~{expected_pro}g, Found {actual_pro}g)")

    # Check Carbs (20 pts)
    if abs(actual_carb - expected_carb) <= tolerance and actual_carb > 0:
        score += 20
        feedback_parts.append(f"✅ Carbs Correct ({actual_carb}g matches {expected_carb}g)")
    else:
        feedback_parts.append(f"❌ Carbs Incorrect (Expected ~{expected_carb}g, Found {actual_carb}g)")

    # Check Fat (20 pts)
    if abs(actual_fat - expected_fat) <= tolerance and actual_fat > 0:
        score += 20
        feedback_parts.append(f"✅ Fat Correct ({actual_fat}g matches {expected_fat}g)")
    else:
        feedback_parts.append(f"❌ Fat Incorrect (Expected ~{expected_fat}g, Found {actual_fat}g)")
        
    # Plan existed and was modified (10 pts anti-gaming)
    if actual_pro > 0 or actual_carb > 0 or actual_fat > 0:
        score += 10
        feedback_parts.append("✅ Plan goals were actively modified from zero.")

    # 5. Trajectory VLM Verification (30 Points Total)
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        vlm_res = query_vlm(prompt=VLM_PROMPT, images=frames)
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            viewed_weight = parsed.get('viewed_weight', False)
            edited_nutrition = parsed.get('edited_nutrition', False)
            
            if viewed_weight and edited_nutrition:
                score += 30
                feedback_parts.append("✅ VLM confirmed trajectory: Viewed weight and edited plan.")
            elif edited_nutrition:
                score += 15
                feedback_parts.append("⚠️ VLM confirmed nutrition edit, but not weight lookup.")
            else:
                feedback_parts.append("❌ VLM did not clearly detect proper UI workflow.")
        else:
            feedback_parts.append(f"⚠️ VLM query failed: {vlm_res.get('error')}")

    # Pass Requirements: Must get the math substantially right (at least 2/3 macros) and show basic edits
    key_criteria_met = score >= 70
    passed = key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }