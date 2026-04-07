#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_download_map_hawaii(traj, env_info, task_info):
    """
    Verifies that the agent downloaded the Hawaii offline map.
    
    Strategy:
    1. Check for file system artifacts (Strongest signal: new file created).
    2. Check VLM trajectory for navigation steps (Menu -> Maps -> US -> Hawaii).
    3. Check VLM final state for "Installed" status.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # 1. Retrieve JSON result and screenshot from device
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        result_data = {}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Score components
    score = 0
    feedback = []
    
    # ---------------------------------------------------------
    # CRITERION 1: File Artifact Check (40 points)
    # ---------------------------------------------------------
    map_found = result_data.get('map_found', False)
    map_size = result_data.get('map_size', 0)
    
    if map_found:
        score += 40
        feedback.append("Map data file detected in storage.")
    else:
        feedback.append("No new map data file detected.")

    # ---------------------------------------------------------
    # CRITERION 2: VLM Trajectory Verification (30 points)
    # ---------------------------------------------------------
    # We want to see the agent navigating the menu hierarchy
    frames = sample_trajectory_frames(traj, n=5)
    
    traj_prompt = """
    Analyze these screenshots from a GPS navigation app. 
    The user should be downloading the map for 'Hawaii'.
    
    Look for these specific steps:
    1. Entering a 'Maps' or 'Manage maps' menu.
    2. Navigating 'North America' -> 'United States'.
    3. Selecting 'Hawaii'.
    4. Pressing a download button.
    
    Did the user perform these steps?
    """
    
    traj_response = query_vlm(
        images=frames,
        prompt=traj_prompt,
        format_response=True
    )
    
    traj_success = traj_response.get('parsed', {}).get('answer', False) if isinstance(traj_response.get('parsed'), dict) else False
    # Fallback to boolean check if VLM returns boolean directly or we parse text
    if not isinstance(traj_success, bool):
        # Basic keyword check in reasoning if parsing fails
        reasoning = str(traj_response.get('reasoning', '')).lower()
        traj_success = 'yes' in reasoning or 'perform' in reasoning

    if traj_success:
        score += 30
        feedback.append("Trajectory confirms navigation through map catalog.")
    else:
        feedback.append("Trajectory verification failed (could not confirm menu navigation).")

    # ---------------------------------------------------------
    # CRITERION 3: VLM Final State Verification (30 points)
    # ---------------------------------------------------------
    final_screenshot = get_final_screenshot(traj)
    
    final_prompt = """
    Analyze this final screenshot of the Sygic GPS 'Manage maps' screen.
    
    Check for the entry 'Hawaii'.
    Does it show indicators that it is INSTALLED/DOWNLOADED?
    
    Indicators of success:
    - A trash can icon (meaning delete is the only option).
    - A checkbox or 'Up to date' text.
    - Absence of a 'cloud' download icon next to Hawaii.
    
    Indicators of failure:
    - A cloud icon or download arrow next to Hawaii.
    - A progress bar that is stuck or incomplete.
    
    Is the Hawaii map successfully installed?
    """
    
    final_response = query_vlm(
        images=[final_screenshot],
        prompt=final_prompt,
        format_response=True
    )
    
    final_success = final_response.get('parsed', {}).get('answer', False) if isinstance(final_response.get('parsed'), dict) else False
    if not isinstance(final_success, bool):
         reasoning = str(final_response.get('reasoning', '')).lower()
         final_success = 'yes' in reasoning or 'installed' in reasoning

    if final_success:
        score += 30
        feedback.append("Final screenshot shows Hawaii map installed.")
    else:
        feedback.append("Final screenshot does not confirm installation.")

    # ---------------------------------------------------------
    # FINAL SCORING
    # ---------------------------------------------------------
    # Pass if map file found OR (Trajectory + Final Visual confirm success)
    # The file check is strict, but sometimes file paths change in updates.
    # VLM is the backup.
    
    passed = False
    if map_found:
        passed = True
    elif traj_success and final_success:
        passed = True
        
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }