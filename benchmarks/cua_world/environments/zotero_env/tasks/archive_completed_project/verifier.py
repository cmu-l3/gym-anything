#!/usr/bin/env python3
"""
Verifier for archive_completed_project task.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_archive_completed_project(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # 1. Verify Archive File (20 points)
    if result.get("export_file_exists") and result.get("file_created_during_task"):
        file_size = result.get("export_file_size", 0)
        if file_size > 100: # Empty RIS file is very small
            score += 20
            feedback_parts.append("Archive file created successfully")
        else:
            score += 5
            feedback_parts.append("Archive file created but seems empty")
    else:
        feedback_parts.append("Archive file not found or not created during task")
        
    db_checks = result.get("db_checks", {})
    total_targets = db_checks.get("total_targets", 3)
    
    # 2. Verify Collection Deleted (20 points)
    if db_checks.get("collection_deleted"):
        score += 20
        feedback_parts.append("Collection deleted")
    else:
        feedback_parts.append("Collection still exists")
        
    # 3. Verify Items Tagged (20 points per item, max 60)
    items_tagged = db_checks.get("items_tagged", 0)
    if items_tagged == total_targets:
        score += 60
        feedback_parts.append(f"All {items_tagged} items tagged correctly")
    elif items_tagged > 0:
        points = int(60 * (items_tagged / total_targets))
        score += points
        feedback_parts.append(f"Partial tagging: {items_tagged}/{total_targets} items tagged")
    else:
        feedback_parts.append("No items tagged with 'submitted-2023'")
        
    # 4. Penalty: Verify Items Preserved (Must not be deleted)
    # If items are missing from library, deduct points severely
    items_preserved = db_checks.get("items_preserved", 0)
    missing = total_targets - items_preserved
    if missing > 0:
        penalty = missing * 20
        score = max(0, score - penalty)
        feedback_parts.append(f"PENALTY: {missing} items were deleted from library!")
    else:
        feedback_parts.append("Items correctly preserved in library")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }