#!/usr/bin/env python3
"""
Verifier for setup_weekly_log_chart task.

Scoring Criteria (100 points total):
1. Workspace Modified (10 pts): Evidence that agent saved their work.
2. Weekly Interval (20 pts): Chart configured to Weekly.
3. Data Load (20 pts): Days to load set to 700.
4. Log Scale (25 pts): Y-Axis set to Logarithmic (Critical).
5. SMA 40 (15 pts): Simple Moving Average (40) present.
6. Image Export (10 pts): Screenshot exported to correct path.

Pass Threshold: 70 points (Must get Log Scale and Weekly Interval to pass usually).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_setup_weekly_log_chart(traj, env_info, task_info):
    """
    Verifies the weekly log chart configuration task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    # Note: Windows path in container, but copy_from_env handles the abstraction usually
    # or we specify the full path. The export script saves to C:\Users\Docker\Desktop\NinjaTraderTasks\...
    remote_result_path = r"C:\Users\Docker\Desktop\NinjaTraderTasks\setup_weekly_log_chart_result.json"
    
    # Temp file for local reading
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(remote_result_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Result file not found. Did the export script run?"
        }
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Error reading result file: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    criteria = result.get("criteria", {})
    workspace_modified = result.get("workspace_modified", False)
    image_exists = result.get("image_exists", False)
    image_fresh = result.get("image_created_during_task", False)

    score = 0
    feedback_parts = []

    # 1. Workspace Modified (10 pts)
    if workspace_modified:
        score += 10
        feedback_parts.append("Workspace saved (+10)")
    else:
        feedback_parts.append("Workspace NOT saved (0)")

    # 2. Weekly Interval (20 pts)
    if criteria.get("PeriodWeekly"):
        score += 20
        feedback_parts.append("Weekly interval set (+20)")
    else:
        feedback_parts.append("Weekly interval NOT found (0)")

    # 3. Data Load (20 pts)
    if criteria.get("DaysLoaded700"):
        score += 20
        feedback_parts.append("Days loaded 700 (+20)")
    else:
        feedback_parts.append("Days loaded incorrect (0)")

    # 4. Log Scale (25 pts)
    if criteria.get("LogScale"):
        score += 25
        feedback_parts.append("Log scale enabled (+25)")
    else:
        feedback_parts.append("Log scale NOT found (0)")

    # 5. SMA 40 (15 pts)
    if criteria.get("SMA40"):
        score += 15
        feedback_parts.append("SMA(40) present (+15)")
    else:
        feedback_parts.append("SMA(40) NOT found (0)")

    # 6. Image Export (10 pts)
    if image_exists and image_fresh:
        score += 10
        feedback_parts.append("Image exported successfully (+10)")
    elif image_exists:
        score += 5
        feedback_parts.append("Image exists but old (+5)")
    else:
        feedback_parts.append("Image NOT exported (0)")

    # Gate: Must have modified workspace OR exported image to get > 0
    if not workspace_modified and not image_exists:
        score = 0
        feedback_parts = ["No evidence of work (no saved workspace or image)"]

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }