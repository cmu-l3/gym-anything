#!/usr/bin/env python3
"""
Verifier for enable_cap_grid_overlay task.
"""

import json
import os
import tempfile
import logging
import xml.etree.ElementTree as ET
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enable_cap_grid_overlay(traj, env_info, task_info):
    """
    Verifies that the CAP Grid Overlay was enabled.
    
    Criteria:
    1. Preference 'ShowCAP' is set to 'true' in shared_prefs XML (40 pts)
    2. Preference file was modified after task start (10 pts)
    3. VLM confirms agent navigated Preferences menu (20 pts)
    4. VLM confirms CAP setting interaction or Grid visibility on map (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env or not query_vlm:
        return {"passed": False, "score": 0, "feedback": "Required environment functions missing"}

    score = 0
    feedback_parts = []
    
    # =========================================================
    # 1. Retrieve Artifacts
    # =========================================================
    temp_dir = tempfile.mkdtemp()
    try:
        # Get result JSON
        result_json_path = os.path.join(temp_dir, "task_result.json")
        copy_from_env("/sdcard/task_result.json", result_json_path)
        
        with open(result_json_path, 'r') as f:
            result = json.load(f)
            
        # Get Prefs XML
        prefs_xml_path = os.path.join(temp_dir, "prefs.xml")
        copy_from_env("/sdcard/final_preferences.xml", prefs_xml_path)
        
        # Get Final Screenshot (for local debugging/logging if needed, though VLM handles it)
        # final_img_path = os.path.join(temp_dir, "final.png")
        # copy_from_env("/sdcard/final_screenshot.png", final_img_path)
        
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task artifacts: {str(e)}"}

    # =========================================================
    # 2. Verify Preferences (Programmatic) - 50 pts total
    # =========================================================
    prefs_valid = False
    prefs_modified = False
    
    try:
        tree = ET.parse(prefs_xml_path)
        root = tree.getroot()
        
        # Look for <boolean name="ShowCAP" value="true" />
        # Note: Keys might be "ShowCAP" or "CAPGrids" depending on version, checking standard "ShowCAP"
        cap_setting = None
        for child in root:
            name = child.get('name', '')
            if name == 'ShowCAP' or name == 'ShowCAPGrids':
                cap_setting = child
                break
        
        if cap_setting is not None:
            value = cap_setting.get('value', 'false')
            if value.lower() == 'true':
                score += 40
                prefs_valid = True
                feedback_parts.append("✅ CAP preference enabled in settings file.")
            else:
                feedback_parts.append("❌ CAP preference found but value is 'false'.")
        else:
            feedback_parts.append("❌ CAP preference key not found in settings.")

        # Check timestamp
        task_start = result.get('task_start', 0)
        prefs_mtime = result.get('prefs_mtime', 0)
        
        # Allow a small buffer or if mtime is slightly weird on Android, 
        # but basically checks if file isn't stale
        if prefs_mtime > task_start:
            score += 10
            prefs_modified = True
            feedback_parts.append("✅ Settings saved during task session.")
        else:
            feedback_parts.append("⚠️ Settings file timestamp not updated (might be old).")

    except Exception as e:
        feedback_parts.append(f"❌ Error parsing preferences XML: {str(e)}")

    # =========================================================
    # 3. Verify Trajectory (VLM) - 50 pts total
    # =========================================================
    # We sample frames to see navigation and final state
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    if final_frame:
        frames.append(final_frame)
        
    vlm_prompt = """
    You are evaluating an agent using the Avare Aviation GPS app.
    The task is to enable the "Civil Air Patrol (CAP) Grid" overlay.
    
    Review the image sequence:
    1. Did the agent open the "Preferences" or "Settings" menu?
    2. Did the agent navigate to "Display" or a map settings section?
    3. Did the agent toggle a setting related to "CAP" or "Civil Air Patrol"?
    4. In the FINAL image, do you see a grid overlay on the map (rectangular boxes, possibly with text codes inside)?
    
    Output JSON:
    {
      "menu_navigated": boolean,
      "setting_toggled": boolean,
      "grid_visible_on_map": boolean,
      "reasoning": "string"
    }
    """
    
    try:
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        vlm_data = vlm_res.get('parsed', {})
        
        # Score Logic
        if vlm_data.get('menu_navigated'):
            score += 20
            feedback_parts.append("✅ VLM confirmed menu navigation.")
        else:
            feedback_parts.append("❌ VLM did not see Preferences menu access.")
            
        if vlm_data.get('setting_toggled') or vlm_data.get('grid_visible_on_map'):
            score += 30
            feedback_parts.append("✅ VLM confirmed CAP setting interaction or visual grid.")
        else:
            feedback_parts.append("❌ VLM did not verify CAP setting change or map grid visibility.")
            
    except Exception as e:
        feedback_parts.append(f"⚠️ VLM verification failed: {str(e)}")
        # Fallback: if programmatic check passed perfectly, give partial credit for VLM failure
        if prefs_valid and prefs_modified:
            score += 30 

    # =========================================================
    # Final Result
    # =========================================================
    # Cleanup
    try:
        import shutil
        shutil.rmtree(temp_dir)
    except:
        pass

    passed = (score >= 60) and prefs_valid
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback_parts)
    }