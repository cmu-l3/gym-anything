#!/usr/bin/env python3
"""
Verifier for enable_timestamp_updates task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enable_timestamp_updates(traj, env_info, task_info):
    """
    Verifies that the agent disabled timestamp preservation and performed a write operation.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: Volume Timestamp Updated (50 points)
    # This proves the setting change actually worked during a write operation
    if result.get("volume_timestamp_updated", False):
        score += 50
        feedback_parts.append("✅ Container timestamp updated successfully")
    else:
        feedback_parts.append("❌ Container timestamp did not update (Setting may still be enabled)")

    # Criterion 2: Config Setting Correct (30 points)
    # Checks the XML file directly
    if result.get("config_correct", False):
        score += 30
        feedback_parts.append("✅ Preference 'PreserveTimestamp' is disabled in config")
    else:
        feedback_parts.append("❌ Preference 'PreserveTimestamp' is NOT disabled in config")

    # Criterion 3: File Written (20 points)
    # Proves the agent actually did the work of copying the file
    if result.get("file_copied_to_volume", False):
        score += 20
        feedback_parts.append("✅ Evidence file found inside volume")
    else:
        feedback_parts.append("❌ Evidence file not found inside volume")

    # Bonus/Penalty: Volume should be dismounted
    if result.get("volume_is_mounted", False):
        score = max(0, score - 5)
        feedback_parts.append("⚠️ Volume was left mounted (should be dismounted)")
    
    passed = score >= 80
    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }