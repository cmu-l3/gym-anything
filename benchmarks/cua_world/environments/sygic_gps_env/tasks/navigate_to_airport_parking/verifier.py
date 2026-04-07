#!/usr/bin/env python3
import json
import os
import tempfile
import logging
import xml.etree.ElementTree as ET
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_navigate_to_airport_parking(traj, env_info, task_info):
    """
    Verifies that the agent navigated to an airport parking garage.
    
    Criteria:
    1. App is running and in navigation mode (30 pts)
    2. Destination name contains "Parking", "Garage", or "Lot" (40 pts)
    3. Workflow Verification (VLM): Agent used contextual search/nearby feature (30 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    score = 0
    feedback_parts = []
    
    # ==========================================================
    # 1. Retrieve Artifacts
    # ==========================================================
    temp_dir = tempfile.mkdtemp()
    result_json_path = os.path.join(temp_dir, "task_result.json")
    ui_dump_path = os.path.join(temp_dir, "ui_dump.xml")
    
    try:
        copy_from_env("/sdcard/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            result_data = json.load(f)
            
        copy_from_env("/sdcard/ui_dump.xml", ui_dump_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task artifacts: {str(e)}"}

    # ==========================================================
    # 2. Check App State (UI Dump Analysis)
    # ==========================================================
    app_running = result_data.get("app_running", False)
    if not app_running:
        return {"passed": False, "score": 0, "feedback": "Sygic app was closed at the end of the task."}
    
    # Analyze UI Dump for Destination Text & Navigation State
    destination_text_found = False
    nav_indicators_found = False # ETA, Distance, Speed
    parking_keywords = ["Parking", "Garage", "Lot", "Valet"]
    found_keywords = []

    try:
        if os.path.exists(ui_dump_path):
            tree = ET.parse(ui_dump_path)
            root = tree.getroot()
            
            # Extract all visible text
            all_text = [node.attrib.get('text', '') for node in root.iter() if node.attrib.get('text')]
            full_text_blob = " ".join(all_text)
            
            # Check for parking keywords
            for kw in parking_keywords:
                if kw.lower() in full_text_blob.lower():
                    found_keywords.append(kw)
            
            if found_keywords:
                destination_text_found = True
            
            # Check for navigation indicators (ETA format like "min", "km", "mi")
            # Sygic typically shows something like "35 min", "24 mi"
            if any(x in full_text_blob for x in ["min", "hr", "km", "mi", "arrival"]):
                nav_indicators_found = True
                
    except Exception as e:
        logger.warning(f"XML parsing failed: {e}")

    # ==========================================================
    # 3. VLM Verification (Workflow & Visual Confirmation)
    # ==========================================================
    frames = sample_trajectory_frames(traj, n=6)
    final_screenshot = get_final_screenshot(traj)
    
    prompt = """
    You are verifying an Android navigation task. 
    The goal is to:
    1. Search for 'San Francisco International Airport' (SFO).
    2. Open the airport's details.
    3. Select a 'Parking' or 'Nearby' option to find a specific parking garage.
    4. Start navigation to that *Parking Garage* (NOT the main airport).

    Review the screenshots and answer:
    1. Did the agent search for SFO?
    2. Did the agent navigate to a parking-specific destination (e.g., 'International Garage', 'Long Term Parking')?
    3. Is the final screen showing active turn-by-turn navigation (map tilted, next turn arrow visible)?
    4. Does the destination name on the final screen confirm it is a Parking facility?

    Output JSON:
    {
        "searched_sfo": true/false,
        "selected_parking_facility": true/false,
        "active_navigation_visible": true/false,
        "destination_is_parking": true/false,
        "destination_name_visible": "string or null"
    }
    """
    
    vlm_result = query_vlm(images=frames + [final_screenshot], prompt=prompt)
    vlm_data = vlm_result.get("parsed", {})
    
    # ==========================================================
    # 4. Scoring
    # ==========================================================
    
    # Criterion 1: Active Navigation (30 pts)
    # Combined signal: UI Dump indicators OR VLM visual confirmation
    if vlm_data.get("active_navigation_visible") or nav_indicators_found:
        score += 30
        feedback_parts.append("Active navigation confirmed.")
    else:
        feedback_parts.append("Navigation does not appear active.")

    # Criterion 2: Correct Destination (Parking) (40 pts)
    # Must be specific garage/parking, not generic airport
    is_parking_dest = vlm_data.get("destination_is_parking") or destination_text_found
    if is_parking_dest:
        score += 40
        kw_str = ", ".join(found_keywords) if found_keywords else "Visual Confirm"
        feedback_parts.append(f"Destination verified as Parking ({kw_str}).")
    else:
        feedback_parts.append("Destination does not appear to be a parking facility.")

    # Criterion 3: Workflow Adherence (30 pts)
    # Did they select a specific facility via the workflow?
    if vlm_data.get("selected_parking_facility"):
        score += 30
        feedback_parts.append("Correct workflow: Selected specific parking facility.")
    elif vlm_data.get("searched_sfo"):
        # Partial credit if they searched SFO but maybe picked parking differently
        score += 10
        feedback_parts.append("Workflow partial: Searched SFO but parking selection unclear.")
    
    # Clean up
    try:
        os.remove(result_json_path)
        os.remove(ui_dump_path)
        os.rmdir(temp_dir)
    except:
        pass

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }