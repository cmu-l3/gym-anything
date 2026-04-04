#!/usr/bin/env python3
"""
Verifier for reproject_view_crs task.

This verifier checks:
1. If the user saved the project file to the correct path.
2. If the file is valid (non-empty, created during task).
3. If the file contains internal references to EPSG:3857 or Web Mercator.
4. If the file is different from the starting project (ensuring changes were made).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reproject_view_crs(traj, env_info, task_info):
    """
    Verify that the view CRS was changed to EPSG:3857 and project saved.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment connection error: copy_from_env not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring criteria
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. File Existence (20 points)
    if result.get("file_exists", False):
        score += 20
        feedback_parts.append("Project file saved correctly.")
    else:
        return {"passed": False, "score": 0, "feedback": "Target project file 'mercator_project.gvsproj' was not found."}

    # 2. File Validity & Timestamp (20 points)
    # Must be > 1KB (empty file check) and created during task
    size = result.get("file_size_bytes", 0)
    created_during = result.get("file_created_during_task", False)
    
    if size > 1000:
        score += 10
        feedback_parts.append("File size is valid.")
    else:
        feedback_parts.append(f"File seems corrupted or empty ({size} bytes).")

    if created_during:
        score += 10
        feedback_parts.append("File created during task session.")
    else:
        feedback_parts.append("File timestamp indicates it was not created during this task.")

    # 3. Content Verification (40 points)
    # Check if CRS 3857 is referenced in the file
    crs_found = result.get("crs_reference_found", False)
    crs_detail = result.get("crs_match_detail", "")
    
    if crs_found:
        score += 40
        feedback_parts.append(f"Confirmed EPSG:3857/Mercator projection in file ({crs_detail}).")
    else:
        feedback_parts.append("Could not find reference to EPSG:3857 or Web Mercator in the saved project.")

    # 4. Modification Verification (20 points)
    # Check if file differs from base project
    differs = result.get("file_differs_from_base", False)
    if differs:
        score += 20
        feedback_parts.append("Project file differs from the original base project.")
    else:
        feedback_parts.append("Saved project is identical to the starting project (no changes detected).")

    # Pass logic
    # We require the file to exist, have the CRS reference, and be modified
    passed = (result.get("file_exists") and 
              result.get("crs_reference_found") and 
              result.get("file_differs_from_base"))
              
    final_feedback = " ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback
    }