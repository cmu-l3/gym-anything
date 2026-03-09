#!/usr/bin/env python3
"""
Verifier for Establish CI Badge Visibility task.

Checks:
1. Pipeline 'Tailwind-CI' was created.
2. README.md was updated.
3. README.md contains a valid badge markdown.
4. The badge URL links to the correct pipeline (anti-gaming).
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_establish_ci_badge_visibility(traj, env_info, task_info):
    """Verify that CI pipeline is created and badge is added to README."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Define paths
    remote_path = r"C:\Users\Docker\task_results\establish_ci_badge_result.json"
    local_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    local_tmp.close()

    try:
        # Copy result file from Windows VM
        copy_from_env(remote_path, local_tmp.name)
        
        with open(local_tmp.name, "r") as f:
            result = json.load(f)
            
    except Exception as e:
        logger.error(f"Failed to copy/read result: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not retrieve task results. Ensure export script ran successfully. Error: {e}"
        }
    finally:
        if os.path.exists(local_tmp.name):
            os.unlink(local_tmp.name)

    # Scoring
    score = 0
    feedback_parts = []
    
    # 1. Pipeline Created (30 pts)
    if result.get("pipeline_exists", False):
        score += 30
        feedback_parts.append("Pipeline 'Tailwind-CI' created.")
    else:
        feedback_parts.append("Pipeline 'Tailwind-CI' NOT found.")
    
    # 2. Pipeline Named Correctly (10 pts)
    if result.get("pipeline_name_correct", False):
        score += 10
    
    # 3. README Modified (20 pts)
    if result.get("readme_updated", False):
        score += 20
        feedback_parts.append("README.md updated.")
    else:
        feedback_parts.append("README.md was not updated.")

    # 4. Badge Syntax Present (20 pts)
    if result.get("badge_present", False):
        score += 20
        feedback_parts.append("Status badge syntax found.")
    else:
        feedback_parts.append("Status badge markdown NOT found in README.")

    # 5. Anti-Gaming: Badge links to correct pipeline (20 pts)
    if result.get("badge_points_to_correct_pipeline", False):
        score += 20
        feedback_parts.append("Badge links to the correct pipeline ID.")
    elif result.get("badge_present", False) and result.get("pipeline_exists", False):
        feedback_parts.append("Badge found but does not link to the created pipeline (wrong ID/Name).")

    # Pass Threshold
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts),
        "details": result
    }