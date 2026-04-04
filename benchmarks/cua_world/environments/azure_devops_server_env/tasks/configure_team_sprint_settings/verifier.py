#!/usr/bin/env python3
"""
Verifier for configure_team_sprint_settings task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_team_sprint_settings(traj, env_info, task_info):
    """
    Verifies that the team sprint settings were configured correctly.
    
    Criteria:
    1. Working Days: Sunday through Thursday (30 pts)
    2. Bugs Behavior: "asRequirements" (25 pts)
    3. Epics Backlog Visibility: Enabled (20 pts)
    4. Default Iteration: Set to Sprint 1 (25 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define the Windows path where the result was saved
    result_path_win = r"C:\Users\Docker\task_results\configure_team_sprint_settings_result.json"
    
    # Create a temporary file on the host to copy the result to
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Copy result from container
        # Note: copy_from_env usually handles path conversion if needed, but explicit is safer
        # Azure DevOps env is Windows, path uses backslashes
        copy_from_env(result_path_win, temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
            
    except Exception as e:
        logger.error(f"Failed to copy or read result file: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not retrieve task result from agent. Ensure the export script ran successfully. Error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check if API fetch was successful
    if not result.get("fetch_success", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Failed to query Azure DevOps API for team settings verification."
        }

    score = 0
    feedback_parts = []
    
    # ------------------------------------------
    # Criterion 1: Working Days (30 pts)
    # Expected: sunday, monday, tuesday, wednesday, thursday
    # ------------------------------------------
    expected_days = {"sunday", "monday", "tuesday", "wednesday", "thursday"}
    # JSON array from PS comes as list
    actual_days_list = result.get("working_days", [])
    # Normalize to lowercase set
    actual_days = set(day.lower() for day in actual_days_list)
    
    if actual_days == expected_days:
        score += 30
        feedback_parts.append("Working days correctly set to Sun-Thu (+30)")
    else:
        # Partial credit? No, scheduling needs to be exact.
        # Check for specific errors to give feedback
        missing = expected_days - actual_days
        extra = actual_days - expected_days
        feedback_msg = "Working days incorrect."
        if missing:
            feedback_msg += f" Missing: {', '.join(missing)}."
        if extra:
            feedback_msg += f" Extra: {', '.join(extra)}."
        feedback_parts.append(feedback_msg)

    # ------------------------------------------
    # Criterion 2: Bugs Behavior (25 pts)
    # Expected: "asRequirements"
    # ------------------------------------------
    actual_bugs = result.get("bugs_behavior", "").lower()
    if actual_bugs == "asrequirements":
        score += 25
        feedback_parts.append("Bugs behavior correctly set to 'Managed with requirements' (+25)")
    else:
        feedback_parts.append(f"Bugs behavior incorrect. Expected 'asRequirements', got '{actual_bugs}'")

    # ------------------------------------------
    # Criterion 3: Epics Visibility (20 pts)
    # Expected: "Microsoft.EpicCategory": true
    # ------------------------------------------
    visibilities = result.get("backlog_visibilities", {})
    # Key might vary slightly in casing, usually "Microsoft.EpicCategory"
    epic_vis = visibilities.get("Microsoft.EpicCategory", False)
    
    if epic_vis is True:
        score += 20
        feedback_parts.append("Epics backlog visibility enabled (+20)")
    else:
        feedback_parts.append("Epics backlog visibility not enabled")

    # ------------------------------------------
    # Criterion 4: Default Iteration (25 pts)
    # Expected: Path contains "Sprint 1"
    # ------------------------------------------
    default_iter = result.get("default_iteration", {})
    iter_path = default_iter.get("path", "")
    
    if "Sprint 1" in iter_path:
        score += 25
        feedback_parts.append("Default iteration correctly set to Sprint 1 (+25)")
    else:
        feedback_parts.append(f"Default iteration incorrect. Expected 'Sprint 1', got '{iter_path}'")

    # ------------------------------------------
    # Final Result
    # ------------------------------------------
    passed = score >= 50  # Threshold as defined in description
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }