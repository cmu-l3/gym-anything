#!/usr/bin/env python3
"""
Verifier for Add Appointment Category task in FreeMED.

Uses a multi-signal approach:
1. Programmatic database verification (Existence, Values, and Anti-gaming checks).
2. VLM Trajectory Verification to confirm the agent actually interacted with the FreeMED UI.
"""

import sys
import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_vlm_prompt():
    """Build VLM prompt to verify trajectory screenshots."""
    return """Review these sequential screenshots from an agent interacting with the FreeMED Electronic Medical Record system.

Task: The agent was supposed to use the FreeMED graphical interface to configure a new appointment category (or visit type) named 'Diabetes Education' with a duration of 45 minutes.

Check for these indicators of actual UI usage:
1. Did the agent navigate through the FreeMED menus (e.g., Support Data, Configuration, or Scheduler Admin)?
2. Did the agent actively fill out a form with the text "Diabetes Education" and "45"?
3. Is there evidence that the form was saved/submitted (e.g., success message, returning to list view)?
4. Verify the agent did NOT just open a terminal and run raw SQL commands to bypass the UI.

Respond in JSON format:
{
    "used_ui": true/false,
    "entered_data": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of what is visible in the frames."
}"""


def verify_add_appointment_category(traj, env_info, task_info):
    """
    Verify that the appointment category was successfully added.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available in environment."}

    # 1. Retrieve programmatic results from the environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("/tmp/appointment_category_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read exported result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result from environment: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    db_match = result_data.get('db_match', False)
    duration_match = result_data.get('duration_match', False)
    newly_created = result_data.get('newly_created', False)

    # Scoring Criteria 1: Database string match (30 points)
    if db_match:
        score += 30
        feedback_parts.append("Category 'Diabetes Education' found in database.")
    else:
        feedback_parts.append("Category 'Diabetes Education' NOT found in database.")

    # Scoring Criteria 2: Duration match (20 points)
    if duration_match:
        score += 20
        feedback_parts.append("Duration (45 minutes) correctly recorded.")
    elif db_match:
        feedback_parts.append("Duration (45 minutes) missing or incorrect.")

    # Scoring Criteria 3: Anti-gaming check (20 points)
    if newly_created:
        score += 20
        feedback_parts.append("Confirmed record was newly created during task session.")
    elif db_match:
        feedback_parts.append("WARNING: Record existed before task start (Anti-gaming check failed).")

    # 2. Retrieve VLM Verification of Trajectory (30 points)
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        all_frames = frames + [final_frame] if final_frame else frames
        
        query_vlm = env_info.get('query_vlm')
        if query_vlm and all_frames:
            vlm_response = query_vlm(prompt=build_vlm_prompt(), images=all_frames)
            
            if vlm_response.get("success"):
                vlm_parsed = vlm_response.get("parsed", {})
                used_ui = vlm_parsed.get("used_ui", False)
                entered_data = vlm_parsed.get("entered_data", False)
                
                if used_ui and entered_data:
                    score += 30
                    feedback_parts.append("VLM confirmed active UI usage for configuration.")
                else:
                    feedback_parts.append(f"VLM UI check failed. Reasoning: {vlm_parsed.get('reasoning', 'None')}")
            else:
                feedback_parts.append("VLM API check failed, skipping visual verification points.")
        else:
            feedback_parts.append("VLM or frames unavailable, skipping visual verification points.")
    except Exception as e:
        logger.warning(f"VLM trajectory verification encountered an error: {e}")
        feedback_parts.append("VLM verification skipped due to framework error.")

    # Final Evaluation
    # Must have matched in DB and been newly created to pass the minimum threshold
    key_criteria_met = db_match and newly_created
    passed = (score >= 60) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }