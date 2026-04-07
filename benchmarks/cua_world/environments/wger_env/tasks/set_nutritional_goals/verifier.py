#!/usr/bin/env python3
"""
Verifier for Set Nutritional Goals task in wger.

Checks:
1. 'Lean Bulk Plan' exists in the database.
2. The agent successfully set Energy, Protein, Carbohydrates, Fat, and Fiber goals to the exact requested values (within small tolerance).
3. The DB state matches the API state (cross-validation).
4. VLM verification on the trajectory frames to ensure the agent actively interacted with the Nutrition Plan UI or API interface.
"""

import os
import json
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """
Analyze these screenshots from an agent's trajectory working in the wger fitness manager.
The agent was asked to set nutritional goals for a 'Lean Bulk Plan' (Energy: 3200 kcal, Protein: 180 g, Carbs: 400 g, Fat: 90 g, Fiber: 35 g).

Please verify:
1. Did the agent navigate to the nutrition plan area or the API browser (/api/v2/)?
2. Is there evidence that the agent interacted with the goal fields or entered the specified values (3200, 180, 400, 90, 35)?
3. In the final frame, are the updated goals visible in the UI or an API response?

Provide your response in JSON format:
{
    "navigated_to_nutrition": true/false,
    "entered_goal_values": true/false,
    "goals_visible_at_end": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of the workflow observed"
}
"""

def is_within_tolerance(actual, expected, tolerance):
    """Helper to check if actual value is within the allowed tolerance of expected."""
    if actual is None:
        return False
    try:
        actual_float = float(actual)
        expected_float = float(expected)
        return abs(actual_float - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False

def verify_set_nutritional_goals(traj, env_info, task_info):
    """Verifies the nutritional goals were properly set in the database, API, and UI."""
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected = {
        'energy': metadata.get('expected_energy', 3200),
        'protein': metadata.get('expected_protein', 180),
        'carbohydrates': metadata.get('expected_carbohydrates', 400),
        'fat': metadata.get('expected_fat', 90),
        'fiber': metadata.get('expected_fiber', 35),
    }
    tolerances = metadata.get('tolerance', {})

    # 1. Read exported result from environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    db_goals = result.get('db_goals', {})
    api_goals = result.get('api_goals', {})
    
    score = 0
    feedback_parts = []
    
    if not db_goals.get('exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Failed: 'Lean Bulk Plan' could not be found in the database. It may have been deleted."
        }
    
    # 2. Score DB target values
    targets_met = 0
    total_targets = 5
    
    for key in ['energy', 'protein', 'carbohydrates', 'fat', 'fiber']:
        val = db_goals.get(key)
        exp = expected[key]
        tol = tolerances.get(key, 0)
        
        if is_within_tolerance(val, exp, tol):
            score += 15
            targets_met += 1
            feedback_parts.append(f"✅ {key.capitalize()} goal set correctly ({val})")
        else:
            feedback_parts.append(f"❌ {key.capitalize()} goal incorrect (Expected {exp}, got {val})")

    # 3. Check API matches DB (Anti-gaming / Consistency) (10 points)
    api_matches = True
    if api_goals:
        for key in ['energy', 'protein', 'carbohydrates', 'fat', 'fiber']:
            db_val = db_goals.get(key)
            api_val = api_goals.get(key)
            # Both None or both essentially the same
            if db_val is None and api_val is None:
                continue
            if not is_within_tolerance(api_val, db_val if db_val else 0, 0.5):
                api_matches = False
                break
    else:
        api_matches = False

    if api_matches and targets_met > 0:
        score += 10
        feedback_parts.append("✅ API endpoint validates database changes")
    else:
        feedback_parts.append("❌ API validation mismatch or no targets set")

    # 4. VLM Trajectory Verification (15 points)
    vlm_passed = False
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        if frames:
            vlm_response = query_vlm(images=frames, prompt=VLM_PROMPT)
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("navigated_to_nutrition") and parsed.get("entered_goal_values"):
                    vlm_passed = True
                    score += 15
                    feedback_parts.append("✅ VLM verified active interaction with goal setting UI/API")
                else:
                    feedback_parts.append(f"⚠️ VLM did not observe goal entry workflow: {parsed.get('reasoning', '')}")
            else:
                feedback_parts.append("⚠️ VLM request failed or returned invalid response")
        else:
            feedback_parts.append("⚠️ No trajectory frames available for VLM")
    else:
        feedback_parts.append("⚠️ VLM not enabled, skipping visual trajectory verification")
        # Give free points if VLM is unavailable but DB says everything is perfect
        if targets_met == total_targets:
            score += 15

    # 5. Final Pass/Fail criteria
    # Must have set at least 3 goals and scored >= 60 points
    passed = score >= 60 and targets_met >= 3

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": "\n".join(feedback_parts),
        "details": {
            "targets_met": targets_met,
            "api_matches": api_matches,
            "vlm_passed": vlm_passed
        }
    }