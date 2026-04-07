#!/usr/bin/env python3
"""
Verifier for create_custom_exercise task.
Evaluates programmatic database exports and uses VLM to confirm GUI trajectory.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are verifying if a computer agent successfully navigated a fitness application to create a new exercise.
Examine these trajectory screenshots.

Did the agent actually navigate the exercise creation workflow? 
Look for:
1. An "Add Exercise" form being filled out (with fields like Name, Category, Description)
2. A view showing muscle anatomy diagrams or dropdowns where muscles are being selected/assigned

Respond ONLY with a JSON object:
{
    "workflow_navigated": true/false,
    "form_interaction_visible": true/false,
    "muscle_selection_visible": true/false,
    "reasoning": "brief explanation"
}
"""

def verify_create_custom_exercise(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0

    # 1. Fetch and Parse Programmatic Result (DB state)
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    logger.info(f"Database Result: {result}")

    # Check existence (25 points)
    if not result.get("exists", False):
        feedback_parts.append("Exercise 'Sled Push' was NOT found in the database.")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": " | ".join(feedback_parts)
        }
        
    score += 25
    feedback_parts.append("✅ Exercise 'Sled Push' exists")

    # Check category (15 points)
    category = result.get("category", "")
    if "leg" in category.lower():
        score += 15
        feedback_parts.append("✅ Category set to Legs")
    else:
        feedback_parts.append(f"❌ Incorrect category: '{category}'")

    # Check description (15 points)
    description = result.get("description", "").lower()
    if "sled" in description and ("45" in description or "degree" in description) and "leg" in description:
        score += 15
        feedback_parts.append("✅ Description contains required details")
    else:
        feedback_parts.append("❌ Description missing required keywords")

    # Check primary muscle (15 points)
    primary_muscles = [m.lower() for m in result.get("primary_muscles", [])]
    if any("glute" in m for m in primary_muscles):
        score += 15
        feedback_parts.append("✅ Primary muscle 'Gluteus maximus' assigned")
    else:
        feedback_parts.append(f"❌ Missing Gluteus maximus in primary muscles: {primary_muscles}")

    # Check secondary muscle (15 points)
    secondary_muscles = [m.lower() for m in result.get("secondary_muscles", [])]
    if any("gastrocnemius" in m or "calf" in m for m in secondary_muscles):
        score += 15
        feedback_parts.append("✅ Secondary muscle 'Gastrocnemius' assigned")
    else:
        feedback_parts.append(f"❌ Missing Gastrocnemius in secondary muscles: {secondary_muscles}")

    # 2. Verify with VLM for visual trajectory evidence (15 points)
    # This prevents the agent from finding an API backdoor and ensures UI use.
    vlm_points = 0
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=6)
            vlm_response = query_vlm(
                prompt=VERIFICATION_PROMPT,
                images=frames
            )
            parsed = vlm_response.get("parsed", {})
            logger.info(f"VLM Response: {parsed}")
            
            if parsed.get("workflow_navigated", False) or parsed.get("form_interaction_visible", False):
                vlm_points += 15
                feedback_parts.append("✅ VLM confirmed form interaction via UI")
            else:
                feedback_parts.append("❌ VLM did not clearly see the UI exercise form workflow")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append("⚠️ VLM verification skipped/failed")
    else:
        feedback_parts.append("⚠️ VLM not available for UI verification")
        
    score += vlm_points

    # Success thresholds
    # Must have created the exercise + got the category right + assigned at least one muscle group
    key_criteria_met = (result.get("exists", False) and 
                        "leg" in result.get("category", "").lower() and 
                        (any("glute" in m for m in primary_muscles) or any("gastrocnemius" in m or "calf" in m for m in secondary_muscles)))

    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }