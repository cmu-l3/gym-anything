#!/usr/bin/env python3
"""
Verifier for install_custom_csl task.

Verification Strategy:
1. Database Check: Does the style ID exist in the 'styles' table? (60 pts)
2. File Check: Does the .csl file exist in the profile's 'styles' folder? (30 pts)
3. Timestamp Check: Was the file created/modified after the task started? (10 pts)

Pass Threshold: 90 points (Requires full installation)
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_install_custom_csl(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify that the custom citation style was installed correctly."""
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result from container
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/task_result.json", temp.name)
            with open(temp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp.name):
                os.unlink(temp.name)
    except Exception as e:
        logger.error(f"Failed to retrieve result: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve export result: {e}. Was the task completed?",
        }

    score = 0
    feedback_parts = []
    
    # Extract Data
    style_in_db = result.get("style_in_db", False)
    style_file_installed = result.get("style_file_installed", False)
    installed_timestamp = result.get("installed_file_timestamp", 0)
    task_start = result.get("task_start", 0)

    # Criterion 1: Database Registration (60 pts)
    if style_in_db:
        score += 60
        feedback_parts.append("Style registered in Jurism database (+60)")
    else:
        feedback_parts.append("Style NOT found in database")

    # Criterion 2: File Installation (30 pts)
    if style_file_installed:
        score += 30
        feedback_parts.append("Style file found in profile directory (+30)")
    else:
        feedback_parts.append("Style file NOT found in profile directory")

    # Criterion 3: Timestamp / Anti-gaming (10 pts)
    # Only check this if the file exists
    if style_file_installed:
        if installed_timestamp > task_start:
            score += 10
            feedback_parts.append("Installation occurred during task (+10)")
        else:
            feedback_parts.append("Warning: Style file timestamp predates task start")
    
    # Final Score Calculation
    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }