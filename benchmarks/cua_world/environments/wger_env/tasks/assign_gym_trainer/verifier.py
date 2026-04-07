#!/usr/bin/env python3
"""
Verifier for assign_gym_trainer task.

Evaluates:
1. Database State Verification (Primary Truth):
   - Gym still exists (10 points)
   - User still exists (10 points)
   - User assigned to a gym (20 points)
   - User assigned to CORRECT gym (30 points)
   - No extra users created (Anti-gaming) (10 points)
2. Trajectory VLM Verification (20 points):
   - Confirms the agent navigated the gym/user UI, rather than making raw API calls.
"""

import os
import json
import logging
import tempfile

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an AI agent's performance on a fitness manager software (wger).
The agent was asked to assign the user 'maria_coach' to the gym 'Iron Works Fitness Center'.

Look at these screenshots from the agent's session. Did the agent navigate through the application's Gym or User management interface and make user assignment changes?

Respond in JSON format:
{
    "navigated_to_gym_or_users": true/false,
    "reasoning": "brief explanation"
}
"""

def verify_assign_gym_trainer(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Extract JSON results from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    db_state = result.get("db_state", {})
    initial_user_count = result.get("initial_user_count", 0)
    
    score = 0
    feedback_parts = []
    
    # 1. Gym Exists (10 points)
    gym_exists = db_state.get("gym_exists", False)
    target_gym_id = db_state.get("target_gym_id")
    if gym_exists and target_gym_id is not None:
        score += 10
        feedback_parts.append("✅ Target gym exists")
    else:
        feedback_parts.append("❌ Target gym missing/deleted")

    # 2. User Exists (10 points)
    user_exists = db_state.get("user_exists", False)
    if user_exists:
        score += 10
        feedback_parts.append("✅ Target user exists")
    else:
        feedback_parts.append("❌ Target user missing/deleted")

    # 3. Assigned to Gym (20 points)
    user_gym_id = db_state.get("user_gym_id")
    if user_gym_id is not None:
        score += 20
        feedback_parts.append("✅ User assigned to a gym")
    else:
        feedback_parts.append("❌ User is not assigned to any gym")

    # 4. Assigned to CORRECT Gym (30 points)
    correct_gym_assigned = False
    if user_gym_id is not None and target_gym_id is not None and user_gym_id == target_gym_id:
        score += 30
        correct_gym_assigned = True
        feedback_parts.append("✅ User assigned to the CORRECT gym")
    elif user_gym_id is not None:
        feedback_parts.append("❌ User assigned to WRONG gym")

    # 5. Anti-gaming check: User counts (10 points)
    current_user_count = db_state.get("current_user_count", 999)
    if current_user_count <= initial_user_count:
        score += 10
        feedback_parts.append("✅ No spurious users created")
    else:
        feedback_parts.append(f"❌ Extraneous users detected (Initial: {initial_user_count}, Current: {current_user_count})")

    # 6. VLM Trajectory Verification (20 points)
    vlm_passed = False
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        
        if frames and final_screen:
            images = frames + [final_screen]
            vlm_resp = query_vlm(prompt=VLM_PROMPT, images=images)
            
            if vlm_resp and vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                vlm_passed = parsed.get("navigated_to_gym_or_users", False)
                if vlm_passed:
                    score += 20
                    feedback_parts.append("✅ VLM verified UI interaction")
                else:
                    feedback_parts.append("❌ VLM did not observe UI gym/user navigation")
            else:
                feedback_parts.append("⚠️ VLM request failed")
        else:
            feedback_parts.append("⚠️ Could not extract trajectory frames for VLM")
    else:
        feedback_parts.append("⚠️ VLM not enabled")
        score += 20 # Auto-grant if VLM is completely disabled in env

    # Success threshold requires DB truth
    key_criteria_met = (gym_exists and user_exists and correct_gym_assigned)
    passed = key_criteria_met and score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }