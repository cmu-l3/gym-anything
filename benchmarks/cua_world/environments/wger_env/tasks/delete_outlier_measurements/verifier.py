#!/usr/bin/env python3
"""
Verifier for delete_outlier_measurements task.

Verification Strategy:
1. Database Query: Check if Body Fat > 100 is 0 (30 pts)
2. Database Query: Check if Waist > 800 is 0 (30 pts)
3. Database Query: Check if Valid Body Fat >= 5 (15 pts) - Anti-mass-deletion
4. Database Query: Check if Valid Waist >= 5 (15 pts) - Anti-mass-deletion
5. VLM Trajectory Check: Agent navigated and performed deletions (10 pts)
"""

import os
import json
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying if a computer agent successfully completed a data cleanup task in a fitness web application (wger).

The agent's goal was to navigate the "Body Measurements" section and delete two specific typo/outlier records.

Look at these trajectory frames and determine:
1. Did the agent navigate through the measurement categories?
2. Is there visual evidence of the agent clicking 'Delete' (or a trash can icon) and confirming the deletion of records?
3. Did the agent interact with the web interface to accomplish this rather than doing nothing?

Respond in JSON format:
{
    "navigated_measurements": true/false,
    "performed_deletion": true/false,
    "reasoning": "brief explanation"
}
"""

def verify_delete_outliers(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Read exported database results
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

    score = 0
    feedback_parts = []
    
    outlier_bf_count = result.get("outlier_bf_count", 1)
    outlier_waist_count = result.get("outlier_waist_count", 1)
    valid_bf_count = result.get("valid_bf_count", 0)
    valid_waist_count = result.get("valid_waist_count", 0)

    # Check Body Fat outlier deleted
    if outlier_bf_count == 0:
        score += 30
        feedback_parts.append("✅ Body Fat outlier deleted")
    else:
        feedback_parts.append(f"❌ Body Fat outlier still exists (count: {outlier_bf_count})")

    # Check Waist outlier deleted
    if outlier_waist_count == 0:
        score += 30
        feedback_parts.append("✅ Waist outlier deleted")
    else:
        feedback_parts.append(f"❌ Waist outlier still exists (count: {outlier_waist_count})")

    # Check Valid Body Fat preserved
    if valid_bf_count >= 5:
        score += 15
        feedback_parts.append(f"✅ Valid Body Fat entries preserved ({valid_bf_count})")
    else:
        feedback_parts.append(f"❌ Valid Body Fat entries missing/deleted ({valid_bf_count} remaining)")

    # Check Valid Waist preserved
    if valid_waist_count >= 5:
        score += 15
        feedback_parts.append(f"✅ Valid Waist entries preserved ({valid_waist_count})")
    else:
        feedback_parts.append(f"❌ Valid Waist entries missing/deleted ({valid_waist_count} remaining)")

    # Early failure if the core tasks weren't completed at all or everything was wiped
    key_criteria_met = (outlier_bf_count == 0 and outlier_waist_count == 0) and (valid_bf_count > 0 and valid_waist_count > 0)

    # 2. VLM Trajectory Verification
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            
            if frames and final:
                vlm_result = query_vlm(
                    prompt=VLM_PROMPT,
                    images=frames + [final]
                )
                
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("performed_deletion"):
                        score += 10
                        feedback_parts.append("✅ VLM verified deletion workflow")
                    else:
                        feedback_parts.append("❌ VLM did not observe deletion workflow")
                else:
                    feedback_parts.append("⚠️ VLM query failed")
            else:
                feedback_parts.append("⚠️ Could not extract frames for VLM")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            feedback_parts.append("⚠️ VLM verification error")

    passed = key_criteria_met and (score >= 75)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }