#!/usr/bin/env python3
"""
Verifier for calendar_skills task.

Verification Strategy:
1. Log File Check (40 pts):
   - File exists at expected path.
   - Created during task.
   - Contains at least 3 lines (dates).

2. VLM Trajectory Verification (60 pts):
   - Verifies the agent actually interacted with the Calendar activity.
   - Checks for navigation (month/year changes).
   - Checks for success indicators (completion of levels).
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM utils provided by the framework
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    # Fallback for testing outside framework
    def sample_trajectory_frames(traj, n=5): return []
    def query_vlm(prompt, images): return {"success": False}


def verify_calendar_skills(traj, env_info, task_info):
    """
    Verify the agent completed the GCompris Calendar task.
    """
    # 1. Setup & Data Loading
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # Load result JSON from container
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

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # CRITERION 1: Log File Evidence (40 pts)
    # ------------------------------------------------------------------
    log_exists = result.get("log_file_exists", False)
    log_fresh = result.get("log_created_during_task", False)
    line_count = int(result.get("log_line_count", 0))

    if log_exists:
        if log_fresh:
            score += 10
            feedback_parts.append("Log file created.")
            
            # Check content volume
            if line_count >= 3:
                score += 30
                feedback_parts.append(f"Log contains {line_count} entries (target: 3+).")
            elif line_count > 0:
                score += 15
                feedback_parts.append(f"Log contains {line_count} entries (target: 3+).")
            else:
                feedback_parts.append("Log file is empty.")
        else:
            feedback_parts.append("Log file exists but was not created during this task (stale).")
    else:
        feedback_parts.append("Log file not found.")

    # ------------------------------------------------------------------
    # CRITERION 2: VLM Trajectory Analysis (60 pts)
    # ------------------------------------------------------------------
    # We need to ensure the agent didn't just write a fake file.
    # The VLM checks if they actually used the calendar UI.
    
    frames = sample_trajectory_frames(traj, n=6)
    
    vlm_prompt = """
    You are verifying an agent's interaction with the GCompris 'Calendar' educational activity.
    The agent should:
    1. Navigate to the Calendar activity (looks like a calendar grid).
    2. Change the Year and Month using arrows.
    3. Select days on the grid.
    4. Receive success feedback (animations, thumbs up, flowers, etc.).

    Review the sequence of images and determine:
    - IS_CALENDAR_VISIBLE: Is the Calendar activity interface visible in at least one frame?
    - NAVIGATION_OCCURRED: Did the displayed Month or Year change between frames?
    - SUCCESS_SEEN: Is there any visual indication of a correct answer (smiley, flower icon, star, Tux thumbs up)?

    Return JSON:
    {
        "calendar_visible": boolean,
        "navigation_occurred": boolean,
        "success_seen": boolean,
        "reasoning": "string"
    }
    """

    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("calendar_visible", False):
            vlm_score += 20
            feedback_parts.append("Calendar interface detected.")
        else:
            feedback_parts.append("Calendar interface NOT detected in screenshots.")
            
        if parsed.get("navigation_occurred", False):
            vlm_score += 20
            feedback_parts.append("Date navigation observed.")
            
        if parsed.get("success_seen", False):
            vlm_score += 20
            feedback_parts.append("Success/completion feedback observed.")
            
        feedback_parts.append(f"VLM Analysis: {parsed.get('reasoning', 'No reasoning provided')}")
    else:
        feedback_parts.append("VLM verification failed (technical error).")
        # Fallback: if log file is perfect, give partial VLM points assuming valid effort
        if score >= 30:
            vlm_score += 10
            feedback_parts.append("Awarding fallback points due to VLM failure.")

    score += vlm_score

    # ------------------------------------------------------------------
    # FINAL SCORING
    # ------------------------------------------------------------------
    passed = (score >= 70) and (log_exists) and (log_fresh)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }