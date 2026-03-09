#!/usr/bin/env python3
"""
Verifier for metadata_dependency_cleanup task.

Criteria:
1. Target Data Element must be DELETED (it should not exist). (50 pts)
2. Container Dataset must EXIST (should not be deleted). (25 pts)
3. Container Group must EXIST (should not be deleted). (25 pts)

If the setup failed (IDs missing), score is 0.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_metadata_cleanup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract flags
    de_exists = result.get("target_de_exists", True)  # Default True (failure state for DE)
    ds_exists = result.get("container_ds_exists", False)
    grp_exists = result.get("container_grp_exists", False)
    
    # Check if IDs were valid (anti-gaming check against setup failure)
    ids = result.get("task_ids", {})
    if ids.get("de_id") == "missing":
        return {"passed": False, "score": 0, "feedback": "Task setup failed to create objects."}

    score = 0
    feedback_parts = []

    # Criterion 1: Data Element Deleted (50 pts)
    if not de_exists:
        score += 50
        feedback_parts.append("✅ Data Element successfully deleted.")
    else:
        feedback_parts.append("❌ Target Data Element still exists.")

    # Criterion 2: Dataset Preserved (25 pts)
    if ds_exists:
        score += 25
        feedback_parts.append("✅ Container Dataset preserved.")
    else:
        feedback_parts.append("❌ Container Dataset was deleted (should have been kept).")

    # Criterion 3: Group Preserved (25 pts)
    if grp_exists:
        score += 25
        feedback_parts.append("✅ Container Group preserved.")
    else:
        feedback_parts.append("❌ Container Group was deleted (should have been kept).")

    # Pass threshold: 100 points (Task is binary in nature: did you clean it up correctly?)
    # We might allow 90 if there's some minor issue, but strictly speaking, destroying the container is bad admin practice.
    # However, if they deleted the DE but also the DS, they get 75. We set pass at 100 for "clean" execution, 
    # or 50 if they just brute forced it? 
    # Let's set pass threshold to 100 because preserving data integrity is the core lesson.
    
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }