#!/usr/bin/env python3
"""Verifier for create_camouflaged_volume task."""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_camouflaged_volume(traj, env_info, task_info):
    """
    Verify the camouflaged volume creation task.
    
    Criteria:
    1. File exists at /home/ga/Volumes/legacy_driver_backup.iso (10 pts)
    2. File is a valid VeraCrypt container (mountable with correct password) (30 pts)
    3. Volume contains the expected sensitive file (20 pts)
    4. Metadata Camouflage: Timestamp is set to June 15, 2021 10:00 (30 pts)
    5. Operational Security: Volume is not mounted at end of task (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_size_mb = metadata.get('expected_size_mb', 50)
    
    # Target timestamp components
    target_year = int(metadata.get('target_year', 2021))
    target_month = int(metadata.get('target_month', 6))
    target_day = int(metadata.get('target_day', 15))
    target_hour = int(metadata.get('target_hour', 10))
    target_minute = int(metadata.get('target_minute', 0))

    score = 0
    feedback_parts = []
    
    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
            
        # 1. File Existence & Size (10 pts)
        if result.get('file_exists'):
            size_mb = result.get('file_size_bytes', 0) / (1024 * 1024)
            if 40 <= size_mb <= 60: # Allow some overhead/tolerance
                score += 10
                feedback_parts.append(f"File exists with correct size ({size_mb:.1f}MB)")
            else:
                score += 5
                feedback_parts.append(f"File exists but size mismatch ({size_mb:.1f}MB, expected ~{expected_size_mb}MB)")
        else:
            feedback_parts.append("Target file legacy_driver_backup.iso not found")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

        # 2. Volume Validity (30 pts)
        if result.get('volume_valid'):
            score += 30
            feedback_parts.append("Volume is a valid VeraCrypt container")
        else:
            feedback_parts.append("File is not a valid container or password incorrect")

        # 3. Content Integrity (20 pts)
        if result.get('content_found'):
            score += 20
            feedback_parts.append("Sensitive file found inside volume")
        else:
            feedback_parts.append("Sensitive file MISSING from volume")

        # 4. Metadata Camouflage (30 pts)
        mtime_epoch = result.get('mtime_epoch', 0)
        mtime_str = result.get('mtime_str', 'Unknown')
        
        # We need to check if the timestamp matches 2021-06-15 10:00
        # Since timezone might vary, we check the datetime components or a window
        try:
            # Parse the mtime_str if possible, or convert epoch to datetime
            dt = datetime.fromtimestamp(mtime_epoch)
            
            # Check accuracy with 1-minute tolerance (since seconds might not be set by touch)
            matches_date = (dt.year == target_year and 
                            dt.month == target_month and 
                            dt.day == target_day)
            
            matches_time = (dt.hour == target_hour and 
                            abs(dt.minute - target_minute) <= 1)
                            
            if matches_date and matches_time:
                score += 30
                feedback_parts.append(f"Timestamp camouflage successful ({dt.strftime('%Y-%m-%d %H:%M')})")
            elif matches_date:
                score += 15
                feedback_parts.append(f"Timestamp date correct, but time incorrect ({dt.strftime('%Y-%m-%d %H:%M')})")
            else:
                feedback_parts.append(f"Timestamp camouflage failed (Found: {dt.strftime('%Y-%m-%d %H:%M')})")
        except Exception as e:
            feedback_parts.append(f"Error validating timestamp: {e}")

        # 5. Clean State (10 pts)
        if not result.get('is_mounted_at_end'):
            score += 10
            feedback_parts.append("Volume cleanly dismounted")
        else:
            feedback_parts.append("Security Violation: Volume left mounted")
            
        # Anti-gaming check: Ensure file was touched/created during task window
        # ctime (change time) updates on chmod/chown/touch and cannot be backdated easily by user
        # It should be > task_start_time
        task_start = result.get('task_start_time', 0)
        ctime = result.get('ctime_epoch', 0)
        
        if ctime < task_start:
            score = 0
            feedback_parts = ["ANTI-GAMING: File metadata indicates it was not modified during this task session."]
            
    except Exception as e:
        logger.error(f"Verification Logic Error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification logic error: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    passed = score >= 90
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }