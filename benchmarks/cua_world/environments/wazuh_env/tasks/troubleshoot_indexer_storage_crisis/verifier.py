#!/usr/bin/env python3
"""
Verifier for Indexer Storage Crisis Task
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_indexer_recovery(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Deleted legacy indices (wazuh-alerts-2023.*)
    2. Removed the read-only block
    3. Successfully restored write capability
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Check 1: Legacy Indices Deleted (40 pts)
    legacy_count = result.get("legacy_indices_count", -1)
    if legacy_count == 0:
        score += 40
        feedback_parts.append("Legacy indices successfully deleted.")
    else:
        feedback_parts.append(f"Legacy indices still present (Count: {legacy_count}).")

    # Check 2: Read-Only Block Removed (40 pts)
    is_read_only = result.get("is_read_only", True)  # Default to True (fail) if missing
    if is_read_only is False:
        score += 40
        feedback_parts.append("Read-only block successfully removed.")
    else:
        feedback_parts.append("Index is still in read-only state.")

    # Check 3: Write Capability Restored (20 pts)
    write_success = result.get("write_success", False)
    if write_success:
        score += 20
        feedback_parts.append("Cluster accepts new writes.")
    else:
        feedback_parts.append("Cluster rejected test write operation.")

    passed = (score >= 80)  # Must minimally delete data and unlock

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }