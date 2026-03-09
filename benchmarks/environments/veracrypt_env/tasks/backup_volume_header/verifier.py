#!/usr/bin/env python3
"""
Verifier for backup_volume_header task.

Verification Strategy:
1. Check if backup file exists and has correct file size (131072 bytes).
2. Check if backup file was created during the task (anti-gaming).
3. Check if original volume is intact (checksum match).
4. Functional Test: Verify the backup can actually restore a corrupted volume.
5. Check if volume was properly dismounted (cleanup).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_backup_volume_header(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_size = metadata.get('expected_size_bytes', 131072)
    
    score = 0
    max_score = 100
    feedback_parts = []
    
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

    # 1. File Existence (20 pts)
    if result.get('file_exists'):
        score += 20
        feedback_parts.append("Backup file exists")
    else:
        feedback_parts.append("Backup file NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. File Size (20 pts)
    # VeraCrypt header backups are exactly 128KB (131072 bytes)
    file_size = result.get('file_size', 0)
    if file_size == expected_size:
        score += 20
        feedback_parts.append(f"File size correct ({file_size} bytes)")
    elif 0 < file_size <= 262144: # Allow small margin or double backup
        score += 10
        feedback_parts.append(f"File size reasonable but not exact ({file_size} bytes)")
    else:
        feedback_parts.append(f"File size incorrect ({file_size} bytes)")

    # 3. Anti-gaming: Created during task (15 pts)
    if result.get('file_created_during_task'):
        score += 15
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp pre-dates task (anti-gaming)")

    # 4. Original Volume Integrity (10 pts)
    if result.get('original_intact'):
        score += 10
        feedback_parts.append("Original volume intact")
    else:
        feedback_parts.append("Original volume modified or corrupted")

    # 5. Functional Validation (35 pts)
    # The gold standard: can we actually use this file to restore a header?
    if result.get('functional_restore_success'):
        score += 35
        feedback_parts.append("Functional restore test PASSED")
    else:
        feedback_parts.append("Functional restore test FAILED (backup may be invalid)")

    # 6. Cleanup check (penalty only)
    if result.get('volume_left_mounted'):
        score = max(0, score - 5)
        feedback_parts.append("Penalty: Volume left mounted")
    else:
        feedback_parts.append("Volume unmounted correctly")

    passed = score >= 80 and result.get('functional_restore_success')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }