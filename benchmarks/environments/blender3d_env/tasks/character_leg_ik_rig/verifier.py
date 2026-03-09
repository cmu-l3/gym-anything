#!/usr/bin/env python3
"""
Verifier for character_leg_ik_rig task.
Scores the agent on setting up the IK constraint, targets, and testing the pose.
"""

import json
import os
import sys
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_leg_rig(traj, env_info, task_info):
    """
    Verify the IK rig setup.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Read result from container
    import tempfile
    local_result_path = tempfile.mktemp()
    try:
        copy_from_env("/tmp/task_result.json", local_result_path)
        with open(local_result_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(local_result_path):
            os.remove(local_result_path)

    # Check for basic file errors
    if not result.get("valid_blend"):
        return {"passed": False, "score": 0, "feedback": "No valid Blender file found or file not modified."}

    score = 0
    feedback_items = []

    # 1. Check Constraint Existence (20 pts)
    if result.get("constraint_found"):
        score += 20
        feedback_items.append("✅ IK Constraint added to Shin.L")
    else:
        feedback_items.append("❌ IK Constraint NOT found on Shin.L")

    # 2. Check Targets (20 pts)
    # Target should be LegRig -> Foot_IK.L
    target_obj = result.get("target_obj", "")
    subtarget = result.get("subtarget_bone", "")
    if target_obj == "LegRig" and subtarget == "Foot_IK.L":
        score += 20
        feedback_items.append("✅ IK Target correct (Foot_IK.L)")
    else:
        feedback_items.append(f"❌ IK Target incorrect (Found: {target_obj} -> {subtarget})")

    # 3. Check Pole Target (20 pts)
    # Pole should be LegRig -> Knee_Target.L
    pole_obj = result.get("pole_target_obj", "")
    pole_sub = result.get("pole_subtarget_bone", "")
    if pole_obj == "LegRig" and pole_sub == "Knee_Target.L":
        score += 20
        feedback_items.append("✅ Pole Target correct (Knee_Target.L)")
    else:
        feedback_items.append(f"❌ Pole Target incorrect (Found: {pole_obj} -> {pole_sub})")

    # 4. Check Chain Length (20 pts)
    # Must be 2 (Shin + Thigh)
    chain_len = result.get("chain_length", 0)
    if chain_len == 2:
        score += 20
        feedback_items.append("✅ Chain Length correct (2)")
    else:
        feedback_items.append(f"❌ Chain Length incorrect (Found: {chain_len}, Expected: 2)")

    # 5. Check Pose (20 pts)
    # The knee must be displaced from rest, proving the rig works and was tested
    if result.get("knee_bent"):
        score += 20
        feedback_items.append("✅ Leg is posed (Knee bent)")
    else:
        feedback_items.append("❌ Leg appears unposed (Knee at rest position). Did you test the rig?")

    # Final result
    passed = score >= 70
    feedback = " | ".join(feedback_items)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": result
    }