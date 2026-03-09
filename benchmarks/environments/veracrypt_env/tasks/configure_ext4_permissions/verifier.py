#!/usr/bin/env python3
"""
Verifier for configure_ext4_permissions task.

Checks:
1. Volume creation and mountability (20 pts)
2. Filesystem is Ext4 (30 pts) - Critical for permissions
3. Script is executable (25 pts)
4. Directory has strict 700 permissions (25 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_ext4_permissions(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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
    
    # Criterion 1: Volume Created & Mountable (20 pts)
    if result.get('volume_exists', False) and result.get('mount_success', False):
        score += 20
        feedback_parts.append("Volume created and mountable")
    else:
        return {"passed": False, "score": 0, "feedback": "Volume not created or cannot be mounted with correct password"}

    # Criterion 2: Filesystem Type (30 pts)
    fs_type = result.get('filesystem_type', 'unknown').lower()
    if 'ext4' in fs_type or 'ext3' in fs_type:
        score += 30
        feedback_parts.append(f"Filesystem is correct ({fs_type})")
    elif 'fat' in fs_type or 'vfat' in fs_type or 'exfat' in fs_type:
        feedback_parts.append(f"Incorrect filesystem: {fs_type} (Permissions not supported)")
    else:
        feedback_parts.append(f"Unknown/Incorrect filesystem: {fs_type}")

    # Criterion 3: Script Executable (25 pts)
    # Note: If FS is FAT, executable bit checks usually fail or return 777 for everything
    if result.get('script_exists', False):
        if result.get('script_executable', False):
            # Anti-gaming: Ensure it's not just because FAT mounts everything as +x
            if 'ext' in fs_type:
                score += 25
                feedback_parts.append("Script is executable")
            else:
                feedback_parts.append("Script appears executable but wrong filesystem")
        else:
            feedback_parts.append("Script exists but is not executable")
            
        if not result.get('script_content_match', False):
            feedback_parts.append("(Script content incorrect)")
    else:
        feedback_parts.append("Script 'deploy_fix.sh' missing")

    # Criterion 4: Secure Directory Permissions (25 pts)
    if result.get('dir_exists', False):
        mode = str(result.get('dir_mode', '000'))
        if mode == '700':
            score += 25
            feedback_parts.append("Directory has correct 700 permissions")
        else:
            feedback_parts.append(f"Directory has insecure permissions: {mode}")
    else:
        feedback_parts.append("Directory 'ssh_keys' missing")

    passed = score >= 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }