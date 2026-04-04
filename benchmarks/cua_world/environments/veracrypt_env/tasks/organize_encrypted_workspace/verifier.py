#!/usr/bin/env python3
"""
Verifier for organize_encrypted_workspace task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_organize_encrypted_workspace(traj, env_info, task_info):
    """
    Verify the organization and security of the encrypted workspace.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Error copying result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Error reading result file: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    max_score = 100
    feedback_parts = []

    # 1. Volume Dismounted (5 pts)
    if result.get('volume_dismounted'):
        score += 5
        feedback_parts.append("Volume correctly dismounted")
    else:
        feedback_parts.append("Volume left mounted")

    # 2. Filesystem Reformat (Implicit check via permissions, but good to note)
    fs_type = result.get('filesystem_type', 'unknown')
    if 'ext' in fs_type.lower() or 'xfs' in fs_type.lower():
        feedback_parts.append(f"Filesystem reformatted to {fs_type}")
    elif fs_type.lower() == 'vfat' or fs_type.lower() == 'fat':
        feedback_parts.append("Filesystem is still FAT (permissions cannot be secured)")
    
    # 3. Directory Structure (15 pts)
    if result.get('structure_valid'):
        score += 15
        feedback_parts.append("Directory structure correct")
    else:
        feedback_parts.append("Directory structure incorrect")

    # 4. Files Moved (30 pts)
    if result.get('files_moved'):
        score += 30
        feedback_parts.append("Files moved to correct directories")
    else:
        feedback_parts.append("Files not found in expected directories")

    # 5. Root Clean (5 pts)
    if result.get('root_clean'):
        score += 5
        feedback_parts.append("Root directory clean")
    else:
        feedback_parts.append("Original files left in root")

    # 6. Permissions (20 pts)
    if result.get('permissions_valid'):
        score += 20
        feedback_parts.append("Permissions secured (700/600)")
    else:
        feedback_parts.append("Permissions incorrect or filesystem not compatible")

    # 7. Manifest (25 pts total)
    if result.get('manifest_exists'):
        score += 5
        feedback_parts.append("Manifest file exists")
        
        if result.get('manifest_valid'):
            score += 20
            feedback_parts.append("Manifest checksums valid")
        else:
            feedback_parts.append("Manifest checksums INVALID")
    else:
        feedback_parts.append("Manifest file missing")

    # Final logic
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }