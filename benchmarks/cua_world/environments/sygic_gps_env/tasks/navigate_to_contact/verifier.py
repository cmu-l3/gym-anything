#!/usr/bin/env python3
"""
Verifier for navigate_to_contact task in Sygic GPS.

Strategy:
1. VLM Trajectory Analysis: Verify the agent accessed the 'Contacts' tab/search category.
2. VLM Final State Analysis: Verify the final screen shows a calculated route to Jalalabad.
3. Scoring:
   - 10 pts: App running
   - 30 pts: Contacts search accessed (Trajectory)
   - 30 pts: Correct contact 'Dr. Hameed' selected (Trajectory)
   - 30 pts: Route successfully calculated (Final screenshot)
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_navigate_to_contact(traj, env_info, task_info):
    """
    Verify the agent navigated to contact 'Dr. Hameed' and calculated a route.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Retrieve result artifacts
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        result_data = {}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    app_running = result_data.get("app_running", False)

    # 2. VLM Trajectory Analysis (Did they use Contacts?)
    frames = sample_trajectory_frames(traj, n=6)
    
    trajectory_prompt = """
    You are analyzing a user interaction with a GPS navigation app.
    Look at these screenshots in chronological order.
    
    I need to verify if the user performed these specific steps:
    1. Opened the Search interface.
    2. Selected the "Contacts" category or tab (look for specific "Contacts" icon or text).
    3. Selected a contact named "Dr. Hameed".
    4. Granted contacts permission (if a dialog appeared).
    
    Provide your analysis in JSON format:
    {
        "search_opened": boolean,
        "contacts_tab_accessed": boolean,
        "permission_dialog_seen": boolean,
        "contact_hameed_seen": boolean,
        "contact_selected": boolean
    }
    """
    
    traj_response = query_vlm(
        images=frames,
        prompt=trajectory_prompt
    )
    
    traj_analysis = traj_response.get("parsed", {})
    if not traj_response.get("success"):
        logger.warning(f"Trajectory VLM failed: {traj_response.get('error')}")

    # 3. VLM Final State Analysis (Is the route calculated?)
    final_screenshot = get_final_screenshot(traj)
    
    final_prompt = """
    Analyze this final screenshot of Sygic GPS Navigation.
    1. Is a route calculated (blue/colored path line on map)?
    2. Is the destination "Jalalabad" or "Dr. Hameed"?
    3. Is there a "Start" or "Navigate" button visible?
    4. Is the distance shown approximately 100-200 km?
    
    Provide analysis in JSON:
    {
        "route_calculated": boolean,
        "destination_match": boolean,
        "ready_to_navigate": boolean,
        "distance_text": "string or null"
    }
    """
    
    final_response = query_vlm(
        images=[final_screenshot],
        prompt=final_prompt
    )
    
    final_analysis = final_response.get("parsed", {})
    if not final_response.get("success"):
        logger.warning(f"Final state VLM failed: {final_response.get('error')}")

    # 4. Scoring Calculation
    score = 0
    feedback = []

    # Criterion 1: App Running (10 pts)
    if app_running:
        score += 10
    else:
        feedback.append("App was not running at end of task.")

    # Criterion 2: Contacts Accessed (30 pts)
    # Allow passing if they accessed tab OR we clearly saw the contact being selected
    if traj_analysis.get("contacts_tab_accessed") or traj_analysis.get("contact_hameed_seen"):
        score += 30
        feedback.append("Successfully accessed Contacts.")
    else:
        feedback.append("Did not detect access to Contacts list.")

    # Criterion 3: Contact Selected (30 pts)
    if traj_analysis.get("contact_selected") or traj_analysis.get("contact_hameed_seen"):
        score += 30
        feedback.append("Selected 'Dr. Hameed'.")
    else:
        feedback.append("Did not detect selection of 'Dr. Hameed'.")

    # Criterion 4: Route Calculated (30 pts)
    if final_analysis.get("route_calculated") and (final_analysis.get("destination_match") or final_analysis.get("ready_to_navigate")):
        score += 30
        feedback.append("Route successfully calculated.")
    elif final_analysis.get("route_calculated"):
        # Partial credit if route exists but destination unclear
        score += 15
        feedback.append("Route calculated, but destination unconfirmed.")
    else:
        feedback.append("No calculated route visible in final state.")

    passed = score >= 85

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": {
            "trajectory": traj_analysis,
            "final": final_analysis
        }
    }