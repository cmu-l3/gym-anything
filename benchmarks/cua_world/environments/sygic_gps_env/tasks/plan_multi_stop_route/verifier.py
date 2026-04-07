#!/usr/bin/env python3
import json
import os
import tempfile
import logging
import xml.etree.ElementTree as ET
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_plan_multi_stop_route(traj, env_info, task_info):
    """
    Verifies that the agent planned a multi-stop route (Paris -> Dijon -> Lyon).
    
    Strategy:
    1. Programmatic: Check if 'Dijon' and 'Lyon' appear in the UI hierarchy XML.
    2. VLM: Analyze trajectory for 'Add stop' workflow and final route visualization.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Artifacts
    temp_dir = tempfile.mkdtemp()
    result_json_path = os.path.join(temp_dir, "task_result.json")
    ui_dump_path = os.path.join(temp_dir, "task_ui_dump.xml")
    
    try:
        copy_from_env("/sdcard/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            result_data = json.load(f)
            
        # Optional: Copy UI dump if it exists
        if result_data.get("ui_dump_exists"):
            copy_from_env("/sdcard/task_ui_dump.xml", ui_dump_path)
            
    except Exception as e:
        logger.error(f"Failed to copy artifacts: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}

    score = 0
    feedback_parts = []

    # 2. Programmatic Verification (40 points)
    
    # Criterion A: App Running (10 pts)
    if result_data.get("app_running", False):
        score += 10
        feedback_parts.append("App was running.")
    else:
        feedback_parts.append("App was NOT running at end of task.")

    # Criterion B: UI Content Analysis (30 pts)
    # Scan XML for city names
    cities_found = []
    has_route_indicators = False
    
    if os.path.exists(ui_dump_path):
        try:
            tree = ET.parse(ui_dump_path)
            root = tree.getroot()
            # Extract all text attributes
            all_text = " ".join([elem.get("text", "") for elem in root.iter() if elem.get("text")]).lower()
            
            if "lyon" in all_text:
                cities_found.append("Lyon")
            if "dijon" in all_text:
                cities_found.append("Dijon")
            if "paris" in all_text:
                cities_found.append("Paris")
                
            # Check for navigation keywords
            nav_keywords = ["km", "min", "h ", "route", "start", "via"]
            if any(k in all_text for k in nav_keywords):
                has_route_indicators = True
                
        except Exception as e:
            logger.warning(f"XML parsing failed: {e}")
            feedback_parts.append("UI dump parsing failed.")

    if "Lyon" in cities_found:
        score += 10
        feedback_parts.append("Lyon found in UI.")
    
    if "Dijon" in cities_found:
        score += 10
        feedback_parts.append("Dijon found in UI.")
        
    if has_route_indicators:
        score += 10
        feedback_parts.append("Route info visible.")

    # 3. VLM Verification (60 points)
    # Using trajectory to verify the *workflow* (search -> route -> add stop)
    
    frames = sample_trajectory_frames(traj, n=5)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying a GPS navigation task. The user must plan a route from Paris to Lyon with a stop in Dijon.
    
    Analyze the screenshots (trajectory and final state).
    
    Check for these specific actions:
    1. Did the user search for a destination (Lyon)?
    2. Did the user use an "Add Stop", "Add Waypoint", or "Via" feature?
    3. Did the user search for the intermediate city (Dijon)?
    4. Does the final screen show a computed route summary (map with blue path, distance, time)?
    5. Does the final route visually appear to go through an intermediate point (not just a straight line)?
    
    Output JSON:
    {
        "searched_destination": true/false,
        "added_stop_workflow": true/false,
        "searched_intermediate": true/false,
        "final_route_visible": true/false,
        "multi_stop_confirmed": true/false,
        "reasoning": "..."
    }
    """
    
    try:
        vlm_response = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        vlm_data = vlm_response.get("parsed", {})
        
        # Scoring logic based on VLM
        if vlm_data.get("searched_destination"):
            score += 10
        else:
            feedback_parts.append("VLM did not see destination search.")
            
        if vlm_data.get("added_stop_workflow") or vlm_data.get("searched_intermediate"):
            score += 20
        else:
            feedback_parts.append("VLM did not see waypoint addition workflow.")
            
        if vlm_data.get("final_route_visible"):
            score += 15
            
        if vlm_data.get("multi_stop_confirmed"):
            score += 15
        else:
            feedback_parts.append("VLM did not confirm multi-stop visualization.")
            
        feedback_parts.append(f"VLM reasoning: {vlm_data.get('reasoning', 'None')}")
        
    except Exception as e:
        logger.error(f"VLM check failed: {e}")
        feedback_parts.append("VLM verification failed to run.")
        # Fallback: if we found both cities in XML, give partial credit for VLM
        if "Lyon" in cities_found and "Dijon" in cities_found:
            score += 30
            feedback_parts.append("Fallback: Cities present in UI, granting partial VLM points.")

    # Final tally
    passed = score >= 70
    
    # Cleanup
    try:
        import shutil
        shutil.rmtree(temp_dir)
    except:
        pass

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }