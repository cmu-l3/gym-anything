#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_set_map_2d_north_up(traj, env_info, task_info):
    """
    Verifies that the agent switched Sygic GPS to 2D North-Up view.
    
    Criteria:
    1. Settings screenshot exists and created during task.
    2. Final map screenshot exists and created during task.
    3. VLM: Settings screenshot shows "2D" or "North Up" selected.
    4. VLM: Final map screenshot shows flat 2D view (no horizon/tilt).
    5. VLM: Trajectory shows navigation through settings menu.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    score = 0
    max_score = 100
    feedback_log = []
    
    # 1. Retrieve Programmatic Results
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    
    try:
        copy_from_env("/sdcard/tasks/set_map_2d_north_up/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results from device"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # Check file existence timestamps (Anti-gaming)
    settings_valid = result_data.get("settings_screenshot_valid", False)
    map_valid = result_data.get("map_screenshot_valid", False)
    
    if settings_valid:
        score += 10
        feedback_log.append("Settings screenshot captured.")
    else:
        feedback_log.append("Settings screenshot missing or old.")
        
    if map_valid:
        score += 10
        feedback_log.append("Final map screenshot captured.")
    else:
        feedback_log.append("Final map screenshot missing or old.")
        
    if not (settings_valid or map_valid):
        return {"passed": False, "score": score, "feedback": "No evidence screenshots provided. " + " ".join(feedback_log)}

    # 2. VLM Verification - Trajectory
    # Check if agent actually went to settings
    frames = sample_trajectory_frames(traj, n=6)
    
    traj_prompt = """
    Analyze these screenshots from an Android GPS navigation app.
    Did the user perform the following steps?
    1. Open the main menu.
    2. Enter 'Settings'.
    3. Enter a 'Map View', 'Map Display', or 'View & Units' section.
    
    Return JSON: {"entered_settings": bool, "found_map_settings": bool}
    """
    
    try:
        traj_response = query_vlm(images=frames, prompt=traj_prompt).get("parsed", {})
        if traj_response.get("entered_settings"):
            score += 10
            feedback_log.append("Agent navigated to settings.")
        if traj_response.get("found_map_settings"):
            score += 15
            feedback_log.append("Agent found map display settings.")
    except Exception as e:
        logger.warning(f"Trajectory VLM check failed: {e}")

    # 3. VLM Verification - Screenshots
    # We retrieve the specific screenshots saved by the agent
    
    # Download Settings Screenshot
    settings_img_path = None
    if settings_valid:
        tf_settings = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(result_data["settings_path"], tf_settings.name)
            settings_img_path = tf_settings.name
            
            settings_prompt = """
            Look at this Sygic GPS settings screen. 
            Is the map view mode set to '2D' or 'North-up'?
            Is '3D' NOT selected?
            
            Return JSON: {"is_2d_selected": bool, "is_north_up_indicated": bool}
            """
            vlm_res = query_vlm(images=[settings_img_path], prompt=settings_prompt).get("parsed", {})
            
            if vlm_res.get("is_2d_selected") or vlm_res.get("is_north_up_indicated"):
                score += 25
                feedback_log.append("Settings verify: 2D/North-up selected.")
            else:
                feedback_log.append("Settings verify: Could not confirm 2D selection.")
                
        except Exception as e:
            logger.error(f"Settings verification failed: {e}")
        finally:
            if settings_img_path and os.path.exists(settings_img_path):
                os.unlink(settings_img_path)

    # Download Map Screenshot
    map_img_path = None
    if map_valid:
        tf_map = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(result_data["map_path"], tf_map.name)
            map_img_path = tf_map.name
            
            map_prompt = """
            Look at this GPS navigation map view.
            1. Is the view a flat, top-down 2D view (like a paper map)?
            2. Is there NO horizon line visible?
            3. Is there NO 3D perspective tilt (buildings/roads looking flat)?
            
            Return JSON: {"is_flat_2d_view": bool, "no_perspective_tilt": bool}
            """
            vlm_res = query_vlm(images=[map_img_path], prompt=map_prompt).get("parsed", {})
            
            if vlm_res.get("is_flat_2d_view") and vlm_res.get("no_perspective_tilt"):
                score += 30
                feedback_log.append("Map verify: View confirmed as 2D/Flat.")
            else:
                feedback_log.append("Map verify: View appears to have 3D perspective or tilt.")
                
        except Exception as e:
            logger.error(f"Map verification failed: {e}")
        finally:
            if map_img_path and os.path.exists(map_img_path):
                os.unlink(map_img_path)

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_log)
    }