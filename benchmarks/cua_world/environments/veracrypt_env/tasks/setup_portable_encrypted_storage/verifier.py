#!/usr/bin/env python3
"""
Verifier for setup_portable_encrypted_storage task.
Checks if the agent created a self-contained portable VeraCrypt setup.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_portable_storage(traj, env_info, task_info):
    """
    Verify the portable storage task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON
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

    score = 0
    feedback_parts = []
    
    # --- Scoring Criteria ---

    # 1. Directory Structure (Total 10)
    if result.get('dir_exists'):
        score += 2
        feedback_parts.append("Root directory created")
    else:
        feedback_parts.append("Root directory missing")
        return {"passed": False, "score": 0, "feedback": "Root directory /home/ga/PortableDrive not found"}

    if result.get('has_mnt'): score += 2; feedback_parts.append("Mount point created")
    else: feedback_parts.append("Mount point missing")

    if result.get('has_readme'): score += 2
    if result.get('readme_content_ok'): score += 4; feedback_parts.append("README valid")
    else: feedback_parts.append("README missing or incomplete")

    # 2. VeraCrypt Binary (Total 8)
    if result.get('has_binary'):
        score += 8
        feedback_parts.append("Binary copied")
    else:
        feedback_parts.append("Binary missing or not executable")

    # 3. Volume Creation (Total 25)
    if result.get('has_vol'):
        score += 5
        # Size check (128MB +/- 5MB)
        size = result.get('vol_size_mb', 0)
        if 123 <= size <= 133:
            score += 5
            feedback_parts.append(f"Volume size correct ({size}MB)")
        else:
            feedback_parts.append(f"Volume size incorrect ({size}MB)")
        
        if result.get('vol_created_during_task'):
            score += 5
        else:
            feedback_parts.append("Volume old/pre-existing")
            
        if result.get('manual_mount_success') or result.get('script_mount_success'):
            score += 10
            feedback_parts.append("Volume mountable with correct password")
        else:
            feedback_parts.append("Volume NOT mountable (wrong password/format)")

    # 4. Volume Content (Total 15)
    if result.get('content_os_release'): score += 10; feedback_parts.append("os-release found")
    else: feedback_parts.append("os-release missing inside volume")
    
    if result.get('content_hostname'): score += 5; feedback_parts.append("hostname found")
    else: feedback_parts.append("hostname missing inside volume")

    # 5. Scripts (Total 27)
    # Mount script
    if result.get('has_mount_sh'):
        score += 2
        if result.get('using_local_binary'): score += 5; feedback_parts.append("mount.sh uses local binary")
        else: feedback_parts.append("mount.sh uses system binary (not portable)")
        
        if result.get('script_mount_success'): score += 8; feedback_parts.append("mount.sh functional")
        else: feedback_parts.append("mount.sh failed to mount")
    else:
        feedback_parts.append("mount.sh missing")

    # Unmount script
    if result.get('has_unmount_sh'):
        score += 4
        if result.get('script_unmount_success'): score += 8; feedback_parts.append("unmount.sh functional")
    else:
        feedback_parts.append("unmount.sh missing")

    # 6. Hygiene (Total 5)
    if not result.get('was_mounted_at_end'):
        score += 5
        feedback_parts.append("Clean dismount at end")
    else:
        feedback_parts.append("Left mounted (penalty)")

    # 7. VLM Verification (Total 10)
    # Check if agent used CLI/Terminal or GUI to do the work. The task implies scripting,
    # so we want to see text editing and likely CLI usage.
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        prompt = (
            "Review these screenshots of a user creating a portable encryption kit. "
            "1. Did the user copy the 'veracrypt' binary? "
            "2. Did the user create shell scripts (mount.sh/unmount.sh)? "
            "3. Did the user interact with the VeraCrypt Volume Creation Wizard or CLI? "
            "Reply with JSON: {'binary_copied': bool, 'scripts_created': bool, 'volume_creation_seen': bool}"
        )
        try:
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('binary_copied'): vlm_score += 3
                if parsed.get('scripts_created'): vlm_score += 4
                if parsed.get('volume_creation_seen'): vlm_score += 3
                feedback_parts.append("VLM verified workflow")
            else:
                # Fallback if VLM fails but programmatic passed
                vlm_score = 5
        except Exception:
            vlm_score = 5
    
    score += vlm_score

    # Threshold
    passed = score >= 65 and result.get('manual_mount_success', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }