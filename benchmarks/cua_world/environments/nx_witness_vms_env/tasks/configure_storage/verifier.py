#!/usr/bin/env python3
"""
Verifier for configure_storage task.
Checks if the correct storage locations were added with specific space limits and types.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_storage(traj, env_info, task_info):
    """
    Verify storage configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define expected values from metadata or defaults
    metadata = task_info.get('metadata', {})
    
    # 50 GB in bytes
    EXPECTED_PRIMARY_BYTES = metadata.get('primary_bytes', 53687091200)
    # 20 GB in bytes
    EXPECTED_BACKUP_BYTES = metadata.get('backup_bytes', 21474836480)
    
    PRIMARY_PATH = metadata.get('primary_path', "/opt/nx_storage/primary")
    BACKUP_PATH = metadata.get('backup_path', "/opt/nx_storage/backup")
    
    TOLERANCE = metadata.get('tolerance_percent', 0.05)

    # Load result file
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

    storages = result.get('current_storages', [])
    initial_count = result.get('initial_storage_count', 0)
    current_count = len(storages)
    
    score = 0
    feedback_parts = []
    
    # Check 1: Storage count increased (Anti-gaming) (5 pts)
    if current_count > initial_count:
        score += 5
        feedback_parts.append("Storage count increased")
    else:
        feedback_parts.append("Storage count did not increase")

    # Find relevant storages
    primary_storage = None
    backup_storage = None
    
    for s in storages:
        url = s.get('url', '')
        if PRIMARY_PATH in url:
            primary_storage = s
        if BACKUP_PATH in url:
            backup_storage = s
            
    # Check 2: Primary Storage Exists (20 pts)
    if primary_storage:
        score += 20
        feedback_parts.append("Primary storage added")
        
        # Check 3: Primary Space Limit (15 pts)
        limit = primary_storage.get('spaceLimitB', 0)
        # Note: spaceLimitB might be 0 if unlimited, but task asked for specific limit
        if (EXPECTED_PRIMARY_BYTES * (1 - TOLERANCE)) <= limit <= (EXPECTED_PRIMARY_BYTES * (1 + TOLERANCE)):
            score += 15
            feedback_parts.append("Primary limit correct")
        else:
            feedback_parts.append(f"Primary limit incorrect ({limit} != {EXPECTED_PRIMARY_BYTES})")
            
        # Check 4: Primary Type (Not Backup) (10 pts)
        if not primary_storage.get('isBackup', False):
            score += 10
            feedback_parts.append("Primary type correct")
        else:
            feedback_parts.append("Primary set as Backup (Wrong)")
    else:
        feedback_parts.append("Primary storage NOT found")

    # Check 5: Backup Storage Exists (20 pts)
    if backup_storage:
        score += 20
        feedback_parts.append("Backup storage added")
        
        # Check 6: Backup Space Limit (15 pts)
        limit = backup_storage.get('spaceLimitB', 0)
        if (EXPECTED_BACKUP_BYTES * (1 - TOLERANCE)) <= limit <= (EXPECTED_BACKUP_BYTES * (1 + TOLERANCE)):
            score += 15
            feedback_parts.append("Backup limit correct")
        else:
            feedback_parts.append(f"Backup limit incorrect ({limit} != {EXPECTED_BACKUP_BYTES})")
            
        # Check 7: Backup Type (Is Backup) (10 pts)
        if backup_storage.get('isBackup', False):
            score += 10
            feedback_parts.append("Backup type correct")
        else:
            feedback_parts.append("Backup NOT set as Backup (Wrong)")
    else:
        feedback_parts.append("Backup storage NOT found")

    # Check 8: Both Enabled (5 pts)
    both_enabled = False
    if primary_storage and backup_storage:
        # 'isEnabled' is the standard field, but 'isOnline' might also be relevant
        # We'll check 'isEnabled' as per API
        p_enabled = primary_storage.get('isEnabled', True)
        b_enabled = backup_storage.get('isEnabled', True)
        if p_enabled and b_enabled:
            score += 5
            both_enabled = True
            feedback_parts.append("Both storages enabled")
        else:
            feedback_parts.append("One or both storages disabled")

    # Final Pass/Fail Logic
    # Must get at least 60 points AND have both storages present to pass reasonably well
    passed = (score >= 60) and (primary_storage is not None) and (backup_storage is not None)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "initial_count": initial_count,
            "current_count": current_count,
            "primary_found": primary_storage is not None,
            "backup_found": backup_storage is not None
        }
    }