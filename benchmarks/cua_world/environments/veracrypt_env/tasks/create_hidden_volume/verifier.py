#!/usr/bin/env python3
"""
Verifier for create_hidden_volume task.
Verifies that:
1. Container file exists and was created during the task.
2. Outer volume mounts with 'CoverStory2024' and contains decoy files.
3. Hidden volume mounts with 'RealSecret!789' and is a separate filesystem.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_hidden_volume(traj, env_info, task_info):
    """
    Verify create_hidden_volume task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define score components
    score = 0
    feedback_parts = []
    
    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying result: {e}")
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result file."}

        with open(temp_result.name, 'r') as f:
            result = json.load(f)
            
        # 1. File Existence & Integrity (20 pts)
        if result.get('file_exists'):
            if result.get('timestamp_valid') and not result.get('is_copy'):
                score += 20
                feedback_parts.append("Container file created successfully.")
            else:
                score += 5
                feedback_parts.append("Container file exists but failed integrity check (old file or copy).")
        else:
            feedback_parts.append("Container file not found.")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

        # 2. Outer Volume (Decoy) (30 pts)
        if result.get('outer_mountable'):
            score += 15
            feedback_parts.append("Outer volume mountable with cover password.")
            
            if result.get('decoy_files_present'):
                score += 15
                feedback_parts.append("Decoy files correctly placed in outer volume.")
            else:
                feedback_parts.append("Decoy files missing from outer volume.")
        else:
            feedback_parts.append("Outer volume failed to mount with cover password.")

        # 3. Hidden Volume (50 pts)
        if result.get('hidden_mountable'):
            score += 40
            feedback_parts.append("Hidden volume mountable with secret password.")
            
            if result.get('filesystems_distinct'):
                score += 10
                feedback_parts.append("Confirmed distinct hidden filesystem.")
            else:
                feedback_parts.append("Warning: Filesystem check inconclusive.")
        else:
            feedback_parts.append("Hidden volume failed to mount (or does not exist).")

    except Exception as e:
        logger.error(f"Verification logic error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification logic error: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Final Pass/Fail logic
    # Must have both mountable to pass plausible deniability requirement
    passed = (result.get('outer_mountable') and 
              result.get('hidden_mountable') and 
              score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }