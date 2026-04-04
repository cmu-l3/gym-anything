#!/usr/bin/env python3
"""
Verifier for configure_secure_mount_permissions task.

SCORING CRITERIA:
1. Volume Mounted (20 pts)
2. Correct Ownership (UID/GID 1000) (30 pts)
3. Secure Permissions (Dir 750, File 640) (30 pts)
4. Write Access Verified (File created + Write probe success) (20 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_secure_mount_permissions(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values
    metadata = task_info.get('metadata', {})
    expected_uid = metadata.get('expected_uid', 1000)
    expected_gid = metadata.get('expected_gid', 1000)
    expected_dir_octal = metadata.get('expected_dir_perms_octal', "750")
    expected_file_octal = metadata.get('expected_file_perms_octal', "640")

    feedback_parts = []
    score = 0
    
    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 1. Volume Mounted
    if result.get('is_mounted', False):
        score += 20
        feedback_parts.append("Volume mounted successfully")
    else:
        return {"passed": False, "score": 0, "feedback": "Volume not mounted"}

    # 2. Ownership Check (UID/GID)
    # Check directory ownership
    dir_uid = result.get('dir_uid', 0)
    dir_gid = result.get('dir_gid', 0)
    
    ownership_ok = (dir_uid == expected_uid and dir_gid == expected_gid)
    
    if ownership_ok:
        score += 30
        feedback_parts.append(f"Ownership correct (UID:{dir_uid}/GID:{dir_gid})")
    else:
        feedback_parts.append(f"Incorrect ownership (Found UID:{dir_uid}/GID:{dir_gid}, Expected {expected_uid}/{expected_gid})")

    # 3. Permissions Check
    # We accept exact matches or safer equivalents (e.g., 700 is safer than 750, but task asked for 750)
    # The task asks for Specific settings: 750 (drwxr-x---) and 640 (-rw-r-----)
    
    dir_octal = str(result.get('dir_octal', '000'))[-3:] # Get last 3 digits
    file_octal = str(result.get('file_octal', '000'))[-3:]
    
    perms_score = 0
    # Directory Perms
    if dir_octal == expected_dir_octal:
        perms_score += 15
        feedback_parts.append(f"Directory permissions correct ({dir_octal})")
    else:
        feedback_parts.append(f"Directory permissions mismatch ({dir_octal} vs {expected_dir_octal})")
        
    # File Perms
    # Note: Sometimes umask 027 results in 640 for files, sometimes 640 is explicit.
    # We also accept 600 or 440 as 'secure enough' fallbacks if we were lenient, 
    # but the task spec was specific. We stick to specific.
    if file_octal == expected_file_octal:
        perms_score += 15
        feedback_parts.append(f"File permissions correct ({file_octal})")
    else:
        feedback_parts.append(f"File permissions mismatch ({file_octal} vs {expected_file_octal})")
        
    score += perms_score

    # 4. Write Access & Test File
    write_score = 0
    # Check if agent created test file
    if result.get('agent_test_file_exists', False):
        # Check ownership of test file too
        if result.get('agent_test_file_uid') == expected_uid:
            write_score += 10
            feedback_parts.append("Test file created by correct user")
        else:
            write_score += 5
            feedback_parts.append("Test file created but wrong owner")
    else:
        feedback_parts.append("Test file 'access_test.txt' not found")
        
    # Check if we can actually write (system verify)
    if result.get('can_write_as_ga', False):
        write_score += 10
        feedback_parts.append("Write access verified")
    else:
        feedback_parts.append("Write access failed for user 'ga'")
        
    score += write_score

    # Final result
    # Pass threshold: 80 points (Must have ownership and write access basically correct)
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }