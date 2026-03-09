#!/usr/bin/env python3
"""
Verifier for configure_encrypted_filesystem_identity task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_encrypted_filesystem_identity(traj, env_info, task_info):
    """
    Verify the VeraCrypt volume creation and filesystem identity configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata expectations
    meta = task_info.get('metadata', {})
    expected_uuid = meta.get('expected_uuid', "550e8400-e29b-41d4-a716-446655440000")
    expected_label = meta.get('expected_label', "TUESDAY_BK")

    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Volume Exists & Created During Task (20 pts)
    if result.get('volume_exists'):
        if result.get('created_during_task'):
            score += 20
            feedback_parts.append("Volume created successfully")
        else:
            score += 5
            feedback_parts.append("Volume exists but timestamp indicates pre-existence (gaming detected?)")
    else:
        feedback_parts.append("Volume file not found")
        return {"passed": False, "score": 0, "feedback": "Volume file not found"}

    # 2. Mountable (Prerequisite for checking internals)
    if not result.get('mount_success'):
        feedback_parts.append("Could not mount volume (wrong password or corrupted)")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. Filesystem Type (10 pts)
    fs_type = result.get('fs_type', '').lower()
    if 'ext4' in fs_type:
        score += 10
        feedback_parts.append("Filesystem is Ext4")
    else:
        feedback_parts.append(f"Filesystem type mismatch: {fs_type}")

    # 4. UUID Match (30 pts)
    actual_uuid = result.get('fs_uuid', '').lower().strip()
    target_uuid = expected_uuid.lower().strip()
    
    if actual_uuid == target_uuid:
        score += 30
        feedback_parts.append("UUID matches exactly")
    elif actual_uuid:
        feedback_parts.append(f"UUID mismatch ({actual_uuid})")
    else:
        feedback_parts.append("UUID not found")

    # 5. Label Match (20 pts)
    actual_label = result.get('fs_label', '').strip()
    if actual_label == expected_label:
        score += 20
        feedback_parts.append("Label matches exactly")
    elif actual_label:
        feedback_parts.append(f"Label mismatch ({actual_label})")
    else:
        feedback_parts.append("Label not found")

    # 6. File Content (10 pts)
    if result.get('file_content_match'):
        score += 10
        feedback_parts.append("Internal identification file verified")
    else:
        feedback_parts.append("Internal identification file missing or incorrect")

    # 7. Clean State / Dismounted (10 pts)
    if not result.get('left_mounted'):
        score += 10
        feedback_parts.append("Volume properly dismounted")
    else:
        feedback_parts.append("Volume was left mounted")

    # Pass logic
    passed = (score >= 70) and (actual_uuid == target_uuid)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }