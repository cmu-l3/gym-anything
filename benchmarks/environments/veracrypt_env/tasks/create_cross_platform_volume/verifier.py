#!/usr/bin/env python3
"""
Verifier for create_cross_platform_volume task.

Criteria:
1. Volume Created (20 pts): Exists, >60MB.
2. Password Works (30 pts): 'ProductionSafe2024!'.
3. Correct Filesystem (30 pts): MUST be 'exfat' or 'fuseblk' (often exfat on Linux).
4. Content (10 pts): Manifest exists.
5. Dismounted (10 pts): Clean state.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_cross_platform_volume(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Volume Creation (20 pts)
    if result.get("volume_exists"):
        size = result.get("volume_size_mb", 0)
        # 64MB requested, allow small variance (60-70)
        if 50 <= size <= 80:
            score += 20
            feedback_parts.append(f"Volume created ({size}MB)")
        else:
            score += 10
            feedback_parts.append(f"Volume created but size mismatch ({size}MB, expected 64MB)")
    else:
        return {"passed": False, "score": 0, "feedback": "No volume file found"}

    # 2. Password Check (30 pts)
    if result.get("password_works"):
        score += 30
        feedback_parts.append("Password accepted")
    else:
        feedback_parts.append("Password rejected (or volume corrupted)")
        # Fail early if we can't mount to check FS
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. Filesystem Check (30 pts) - CRITICAL
    fs_type = result.get("filesystem_type", "").lower()
    # On Linux, exFAT might show as 'exfat' or 'fuseblk' depending on driver
    if "exfat" in fs_type or "fuseblk" in fs_type: 
        # Note: 'fuseblk' is generic, but usually implies ntfs/exfat. 
        # Ideally we'd be stricter, but 'exfat' is the standard output for exfat-utils/exfatprogs.
        # If the user used FAT, it would show 'vfat' or 'msdos'.
        score += 30
        feedback_parts.append(f"Filesystem correct ({fs_type})")
    elif "vfat" in fs_type or "fat" in fs_type or "msdos" in fs_type:
        feedback_parts.append(f"Incorrect filesystem: {fs_type} (likely FAT/FAT32)")
    elif "ext" in fs_type:
        feedback_parts.append(f"Incorrect filesystem: {fs_type} (Linux native)")
    else:
        feedback_parts.append(f"Unknown filesystem: {fs_type}")

    # 4. Content Check (10 pts)
    if result.get("manifest_found"):
        score += 10
        feedback_parts.append("Manifest file found inside")
    else:
        feedback_parts.append("Manifest file missing from volume")

    # 5. Dismount Check (10 pts)
    if result.get("is_dismounted"):
        score += 10
        feedback_parts.append("Volume cleanly dismounted")
    else:
        feedback_parts.append("Volume left mounted")

    # Pass logic: Must have volume, password, and correct FS. 
    # Score max 100. 
    # Threshold 80 implies everything except maybe clean dismount or content is strictly required.
    passed = score >= 80 and ("exfat" in fs_type or "fuseblk" in fs_type)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }