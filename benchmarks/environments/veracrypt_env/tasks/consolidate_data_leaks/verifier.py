#!/usr/bin/env python3
"""
Verifier for consolidate_data_leaks task.

SCORING CRITERIA:
1. Leak Remediation (40 pts): Unencrypted sensitive files removed from home.
2. Data Preservation (40 pts): Sensitive files successfully moved to encrypted volume.
3. Precision (10 pts): Distractor files NOT deleted/moved.
4. Security Hygiene (10 pts): Volume dismounted at the end.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_consolidate_data_leaks(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # 1. Leak Remediation (Max 40)
    # 3 original leaks. Points per leak removed.
    leaks_remaining = result.get("leaks_remaining_in_home", 3)
    leaks_removed = 3 - leaks_remaining
    # Partial points: 13.3 pts per file
    score_remediation = int((leaks_removed / 3) * 40)
    score += score_remediation
    if leaks_remaining == 0:
        feedback_parts.append("All leaks removed from home directories")
    else:
        feedback_parts.append(f"{leaks_remaining} unencrypted leaks still present")

    # 2. Data Preservation (Max 40)
    # Expecting 3 files in volume
    files_in_vol = result.get("sensitive_files_in_volume", 0)
    # Cap at 3 for scoring calculation to avoid bonus for duplicates
    effective_files = min(files_in_vol, 3)
    score_preservation = int((effective_files / 3) * 40)
    score += score_preservation
    
    if not result.get("mount_verification_success"):
        feedback_parts.append("Could not verify volume contents (password/mount failed)")
        score_preservation = 0 # Fail this category if we can't look inside
    else:
        feedback_parts.append(f"{files_in_vol} sensitive files found in encrypted volume")

    # 3. Precision (Max 10)
    distractors_missing = result.get("distractors_missing", 0)
    if distractors_missing == 0:
        score += 10
        feedback_parts.append("Distractor files preserved")
    else:
        feedback_parts.append(f"{distractors_missing} distractor files were incorrectly removed")

    # 4. Security Hygiene (Max 10)
    if not result.get("is_mounted_by_agent"):
        score += 10
        feedback_parts.append("Volume safely dismounted")
    else:
        feedback_parts.append("Security Warning: Volume left mounted")

    # VLM Check (Optional Trajectory Verification)
    # Check if agent was seen using VeraCrypt
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = "Does the user appear to be interacting with the VeraCrypt interface or a file manager in these frames?"
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        if vlm_res.get("success") and "yes" in vlm_res.get("parsed", {}).get("answer", "").lower():
            # Could add bonus points or just use for validation logging
            logger.info("VLM confirmed VeraCrypt interaction")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }