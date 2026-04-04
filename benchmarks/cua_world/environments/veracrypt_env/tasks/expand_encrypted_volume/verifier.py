#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_expand_encrypted_volume(traj, env_info, task_info):
    """
    Verify the expansion of a VeraCrypt volume.
    
    Criteria:
    1. Volume exists and is ~50MB (20 pts)
    2. Volume mounts with original password (15 pts)
    3. Data Integrity: Original files are intact (30 pts)
    4. Marker file created inside volume (10 pts)
    5. Free space indicates successful expansion (10 pts)
    6. Report file created in Documents (10 pts)
    7. Volume is dismounted at the end (5 pts)
    """
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Volume Size (Target 50MB, allow +/- 5MB)
    size = result.get("final_size_mb", 0)
    if 45 <= size <= 55:
        score += 20
        feedback.append(f"Volume size correct ({size}MB)")
    else:
        feedback.append(f"Volume size incorrect ({size}MB, expected ~50MB)")

    # 2. Mount Success
    if result.get("mount_success"):
        score += 15
        feedback.append("Volume mounts with password")
    else:
        feedback.append("Failed to mount volume (wrong password or corrupted)")
        # Critical failure if can't mount
        return {"passed": False, "score": score, "feedback": ". ".join(feedback)}

    # 3. Data Integrity (30 pts total, 10 per file approx)
    # The export script sums up found files (max 3) and checks SHA sums
    files_found = result.get("original_files_found_count", 0)
    integrity_passed = result.get("integrity_passed", False)
    
    if integrity_passed and files_found == 3:
        score += 30
        feedback.append("All original files intact")
    else:
        # Partial credit based on file count if strict integrity check fails
        partial_points = files_found * 5
        score += partial_points
        feedback.append(f"Data integrity check failed (Found {files_found}/3 valid files)")

    # 4. Marker File
    if result.get("marker_file_valid"):
        score += 10
        feedback.append("Marker file found inside volume")
    else:
        feedback.append("Marker file missing or invalid")

    # 5. Free Space (Target: >30MB available)
    free_space = result.get("free_space_mb", 0)
    if free_space >= 30:
        score += 10
        feedback.append(f"Free space verified ({free_space}MB)")
    else:
        feedback.append(f"Insufficient free space ({free_space}MB) - Did expansion work?")

    # 6. Report File
    if result.get("report_valid"):
        score += 10
        feedback.append("Report file valid")
    elif result.get("report_exists"):
        score += 5
        feedback.append("Report file exists but content incomplete")
    else:
        feedback.append("Report file missing")

    # 7. Dismount State
    if not result.get("is_currently_mounted"):
        score += 5
        feedback.append("Volume correctly dismounted")
    else:
        feedback.append("Volume left mounted")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": ". ".join(feedback)
    }