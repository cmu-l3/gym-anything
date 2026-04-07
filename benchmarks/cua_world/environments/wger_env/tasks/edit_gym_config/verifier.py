#!/usr/bin/env python3
"""
Verifier for edit_gym_config task in wger_env.

Evaluates programmatic DB state for exact string matches and incorporates 
VLM trajectory checking to ensure the agent actually used the web UI.
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying if a computer agent successfully navigated and edited a form in a web application.

TASK: The agent needs to navigate to the Gym Management section of the wger fitness app and edit a gym's details (changing name to "Iron Peak Athletics" and adding address/phone information).

Look at these trajectory frames and determine:
1. Did the agent navigate to the Gym/Facilities management section?
2. Did the agent open an edit form for a Gym?
3. Did the agent type/enter any of the requested information (like "Iron Peak Athletics", "Springfield", or the phone number)?

Respond with a JSON object:
{
    "navigated_to_gyms": true/false,
    "edited_form": true/false,
    "entered_data": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""

def verify_edit_gym_config(traj, env_info, task_info):
    """
    Verify the Gym was successfully updated in the DB and visually via VLM.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    old_name = metadata.get('old_name', 'Downtown Fitness Hub')
    expected_name = metadata.get('expected_name', 'Iron Peak Athletics')
    expected_phone = metadata.get('expected_phone', '+1-555-842-9631')
    expected_street = metadata.get('expected_street', '742 Evergreen Terrace')
    expected_city = metadata.get('expected_city', 'Springfield')
    expected_zip = metadata.get('expected_zip', '62704')

    # 1. Retrieve the results
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

    gyms = result.get('gyms', [])
    score = 0
    feedback_parts = []
    
    # 2. Programmatic Database Checks
    # We iterate over values to decouple verification from exact Django model field names
    target_gym = None
    old_gym_exists = False
    
    for g in gyms:
        values = [str(v).lower() for v in g.values() if v is not None]
        
        # Check if this gym is the updated one
        if any(expected_name.lower() in val for val in values):
            target_gym = g
            
        # Check if the old gym name is still lingering around
        if any(old_name.lower() in val for val in values):
            old_gym_exists = True

    if target_gym:
        score += 25
        feedback_parts.append(f"✅ Gym renamed to '{expected_name}'")
        
        target_vals = [str(v).lower() for v in target_gym.values() if v is not None]
        
        if any(expected_phone.lower() in val for val in target_vals):
            score += 15
            feedback_parts.append("✅ Phone updated correctly")
        else:
            feedback_parts.append("❌ Phone mismatch")
            
        if any(expected_street.lower() in val for val in target_vals):
            score += 15
            feedback_parts.append("✅ Street updated correctly")
        else:
            feedback_parts.append("❌ Street mismatch")
            
        if any(expected_city.lower() in val for val in target_vals):
            score += 15
            feedback_parts.append("✅ City updated correctly")
        else:
            feedback_parts.append("❌ City mismatch")
            
        if any(expected_zip.lower() in val for val in target_vals):
            score += 15
            feedback_parts.append("✅ Zip code updated correctly")
        else:
            feedback_parts.append("❌ Zip code mismatch")
    else:
        feedback_parts.append(f"❌ Could not find a gym named '{expected_name}'")

    if not old_gym_exists:
        score += 5
        feedback_parts.append(f"✅ Old gym name '{old_name}' no longer exists (edited successfully)")
    else:
        feedback_parts.append(f"❌ Found a gym still named '{old_name}' (agent may have created a duplicate instead of editing)")

    # 3. VLM Trajectory Check
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=6)
        if frames:
            vlm_response = query_vlm(
                images=frames,
                prompt=VLM_PROMPT
            )
            
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("edited_form") and parsed.get("entered_data"):
                    vlm_score = 10
                    feedback_parts.append("✅ VLM confirmed form interaction workflow")
                else:
                    feedback_parts.append("❌ VLM did not confirm editing workflow in trajectory")
            else:
                feedback_parts.append("⚠️ VLM verification failed or returned invalid response")
        else:
            feedback_parts.append("⚠️ Could not extract frames for VLM verification")
    else:
        feedback_parts.append("⚠️ VLM not available")

    score += vlm_score

    # Passing Criteria: Score >= 70 (meaning the name and at least 3 fields were updated)
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "found_target_gym": target_gym is not None,
            "old_gym_exists": old_gym_exists,
            "vlm_score": vlm_score
        }
    }