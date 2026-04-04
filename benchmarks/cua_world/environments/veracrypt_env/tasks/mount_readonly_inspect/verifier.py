#!/usr/bin/env python3
"""
Verifier for mount_readonly_inspect task.

Verification Criteria:
1. Volume Mounted (20 pts): data_volume.hc is mounted.
2. Mounted Read-Only (25 pts): Mount options include 'ro' or write test fails.
3. Inventory File Exists (15 pts): Output file exists and is non-empty.
4. Inventory Content (25 pts): Contains expected filenames.
5. Inventory Details (10 pts): Contains metadata (sizes/dates).
6. Still Mounted (5 pts): Volume is still mounted at check time.

Pass Threshold: 60 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mount_readonly_inspect(traj, env_info, task_info):
    """
    Verify that the volume was mounted read-only and inventory created.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_files = metadata.get('expected_files', [])
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}

        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        # 1. Volume Mounted (20 pts)
        if result.get('volume_mounted', False) and result.get('mountpoint_valid', False):
            score += 20
            feedback_parts.append("Volume mounted successfully")
        else:
            feedback_parts.append("Volume NOT mounted")

        # 2. Mounted Read-Only (25 pts)
        if result.get('is_read_only', False):
            score += 25
            feedback_parts.append("Read-only mode confirmed")
        else:
            feedback_parts.append("Volume mounted in Read/Write mode (unsafe)")

        # 3. Inventory File Exists (15 pts)
        inventory_exists = result.get('inventory_exists', False)
        inventory_size = result.get('inventory_size', 0)
        task_start = result.get('task_start_time', 0)
        inventory_mtime = result.get('inventory_mtime', 0)
        
        if inventory_exists and inventory_size > 10:
            # Anti-gaming: Check timestamp
            if inventory_mtime >= task_start:
                score += 15
                feedback_parts.append("Inventory file created")
            else:
                score += 5
                feedback_parts.append("Inventory file exists but timestamp predates task")
        else:
            feedback_parts.append("Inventory file missing or empty")

        # 4. Inventory Content (25 pts)
        content = result.get('inventory_content', '')
        files_found = 0
        if inventory_exists:
            for fname in expected_files:
                if fname in content:
                    files_found += 1
            
            # Proportional score
            file_score = int((files_found / len(expected_files)) * 25)
            score += file_score
            feedback_parts.append(f"Inventory lists {files_found}/{len(expected_files)} files")
        
        # 5. Inventory Details (10 pts)
        if result.get('has_details', False):
            score += 10
            feedback_parts.append("Inventory includes file details")
        elif inventory_exists:
            feedback_parts.append("Inventory only contains filenames (missing details)")

        # 6. Still Mounted (5 pts)
        # Assuming verify runs immediately after export, mountpoint_valid covers this
        if result.get('mountpoint_valid', False):
            score += 5
            feedback_parts.append("Volume remains mounted")
        else:
            feedback_parts.append("Volume was dismounted prematurely")

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification logic error: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }