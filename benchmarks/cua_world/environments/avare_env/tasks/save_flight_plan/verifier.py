#!/usr/bin/env python3
"""
Verifier for save_flight_plan task in Avare.

Checks:
1. Anti-gaming: Plan file must be created AFTER task start.
2. File existence: A file named *BayAreaTraining* must exist in Avare's storage.
3. Content: The file must contain the requested waypoints (KPAO, KLVK, KWVI).
4. VLM: Trajectory verification to ensure the agent actually used the UI.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_save_flight_plan(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    # Task constants
    REQUIRED_WAYPOINTS = ["KPAO", "KLVK", "KWVI"]
    PLAN_NAME = "BayAreaTraining"

    # 1. Retrieve result JSON from the environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to retrieve task results from device. Did the agent crash?"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Retrieve Metadata
    plan_found = result_data.get("plan_found", False)
    plan_content = result_data.get("plan_content", "")
    app_running = result_data.get("app_running", False)

    score = 0
    feedback = []

    # Criterion 1: App Running (10 pts)
    if app_running:
        score += 10
        feedback.append("Avare app was running at the end.")
    else:
        feedback.append("Avare app was NOT running.")

    # Criterion 2: Plan File Created (30 pts)
    # The export script already validated the timestamp against task_start
    if plan_found:
        score += 30
        feedback.append(f"Plan file '{PLAN_NAME}' was successfully saved.")
    else:
        feedback.append(f"No plan file named '{PLAN_NAME}' found created during the task.")

    # Criterion 3: Content Verification (30 pts)
    # Check if waypoints are in the file content
    # Avare saves usually in JSON or a custom format, but waypoints are clear text
    waypoints_found = 0
    missing_waypoints = []
    
    if plan_found:
        content_upper = plan_content.upper()
        for wp in REQUIRED_WAYPOINTS:
            if wp in content_upper:
                waypoints_found += 1
            else:
                missing_waypoints.append(wp)
        
        if waypoints_found == len(REQUIRED_WAYPOINTS):
            score += 30
            feedback.append("All required waypoints found in saved plan file.")
        elif waypoints_found > 0:
            partial_score = int(30 * (waypoints_found / len(REQUIRED_WAYPOINTS)))
            score += partial_score
            feedback.append(f"Found {waypoints_found}/{len(REQUIRED_WAYPOINTS)} waypoints. Missing: {', '.join(missing_waypoints)}.")
        else:
            feedback.append("Plan file found but appears empty or missing waypoints.")
    
    # Criterion 4: VLM Verification (30 pts)
    # Verify the workflow: Plan tab -> Entry -> Save dialog
    vlm_score = 0
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)

    if frames:
        prompt = f"""
        Review these screenshots of an agent using the Avare Aviation GPS app.
        I need to verify if the agent created and saved a flight plan.
        
        Look for:
        1. The 'Plan' screen or tab being active.
        2. A list of waypoints including KPAO, KLVK, or KWVI.
        3. A 'Save' dialog or menu option being selected.
        4. The text '{PLAN_NAME}' being entered.
        
        Return a JSON object with:
        {{
            "plan_screen_visible": true/false,
            "waypoints_visible": true/false,
            "save_action_visible": true/false,
            "plan_name_entered": true/false,
            "confidence": 0-10
        }}
        """
        
        try:
            vlm_response = query_vlm(images=frames, prompt=prompt)
            if vlm_response and vlm_response.get("success"):
                analysis = vlm_response.get("parsed", {})
                
                if analysis.get("plan_screen_visible"): vlm_score += 5
                if analysis.get("waypoints_visible"): vlm_score += 10
                if analysis.get("save_action_visible"): vlm_score += 10
                if analysis.get("plan_name_entered"): vlm_score += 5
                
                feedback.append(f"VLM verification confidence: {analysis.get('confidence')}/10")
            else:
                feedback.append("VLM verification failed to process images.")
        except Exception as e:
            logger.warning(f"VLM error: {e}")
            # Fallback: if we found the file perfectly, give partial VLM credit
            if score >= 60:
                vlm_score = 15
                feedback.append("VLM skipped, but file evidence is strong.")

    score += vlm_score

    # Final Pass/Fail
    # Must have the file found AND reasonable content OR very high VLM confidence
    passed = (score >= 70) and plan_found
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }