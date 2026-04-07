#!/usr/bin/env python3
"""
Verifier for reorder_workout_exercises task.

Verifies:
1. Exact number of exercises remains 3 (no accidental deletions/additions).
2. The sequence is strictly: Squat -> Leg Extension -> Calf Raises.
3. Original database objects (manager_set) were preserved and reordered, not deleted and recreated.
4. Trajectory analysis confirms the UI was interacted with appropriately.
"""

import os
import json
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFY_PROMPT = """You are verifying if a user successfully completed a UI interaction task.
Task: "Reorder exercises in a workout routine web interface using drag-and-drop or order arrows."

Look at the provided trajectory frames from the web application (wger fitness manager). 
Did the user interact with the routine editing interface to change the order of exercises (e.g. clicking drag handles, using dropdown menus, or clicking up/down arrows)?

Return a JSON object:
{
    "interaction_visible": true/false,
    "reasoning": "Brief explanation of what the user is doing in the screenshots"
}
"""

def verify_reorder_exercises(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"Task execution error: {result['error']}"}

    score = 0
    feedback_parts = []
    
    id_calf = result.get('id_calf')
    id_legext = result.get('id_legext')
    id_squat = result.get('id_squat')
    
    current_sets = result.get('current_sets', [])
    
    # 1. Verify Set Count (15 points)
    if len(current_sets) == 3:
        score += 15
        feedback_parts.append("✅ Exactly 3 exercises remain")
    else:
        feedback_parts.append(f"❌ Expected 3 exercises, found {len(current_sets)}. Deletion/Addition occurred.")
        
    # Variables to track entity preservation
    entities_preserved = True
    
    # Check sequences safely
    if len(current_sets) > 0:
        ex1 = current_sets[0]
        if 'squat' in ex1['exercise'].lower():
            score += 15
            if ex1['id'] == id_squat:
                score += 10
                feedback_parts.append("✅ Squat is 1st (Entity Preserved)")
            else:
                entities_preserved = False
                feedback_parts.append("⚠️ Squat is 1st (But was deleted & recreated)")
        else:
            feedback_parts.append(f"❌ 1st exercise is {ex1['exercise']}, expected Squat")
            
    if len(current_sets) > 1:
        ex2 = current_sets[1]
        if 'leg ext' in ex2['exercise'].lower():
            score += 15
            if ex2['id'] == id_legext:
                score += 10
                feedback_parts.append("✅ Leg Extension is 2nd (Entity Preserved)")
            else:
                entities_preserved = False
                feedback_parts.append("⚠️ Leg Extension is 2nd (But was deleted & recreated)")
        else:
            feedback_parts.append(f"❌ 2nd exercise is {ex2['exercise']}, expected Leg Extension")

    if len(current_sets) > 2:
        ex3 = current_sets[2]
        if 'calf' in ex3['exercise'].lower():
            score += 15
            if ex3['id'] == id_calf:
                score += 10
                feedback_parts.append("✅ Calf Raises is 3rd (Entity Preserved)")
            else:
                entities_preserved = False
                feedback_parts.append("⚠️ Calf Raises is 3rd (But was deleted & recreated)")
        else:
            feedback_parts.append(f"❌ 3rd exercise is {ex3['exercise']}, expected Standing Calf Raises")

    # Anti-gaming: Do Nothing Check
    if current_sets and len(current_sets) >= 3:
        if current_sets[0]['id'] == id_calf and current_sets[1]['id'] == id_legext and current_sets[2]['id'] == id_squat:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Do Nothing detected: Exercises are still in the original incorrect order.",
                "details": {"original_order_retained": True}
            }

    # 4. VLM Trajectory Verification (10 points)
    vlm_passed = False
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        if final:
            frames.append(final)
            
        if frames:
            vlm_response = query_vlm(images=frames, prompt=VERIFY_PROMPT)
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("interaction_visible", False):
                    score += 10
                    vlm_passed = True
                    feedback_parts.append("✅ VLM confirmed trajectory UI interaction")
                else:
                    feedback_parts.append("❌ VLM did not observe reordering UI interaction")
            else:
                feedback_parts.append("⚠️ VLM query failed")
    
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "entities_preserved": entities_preserved,
            "vlm_verification_passed": vlm_passed
        }
    }