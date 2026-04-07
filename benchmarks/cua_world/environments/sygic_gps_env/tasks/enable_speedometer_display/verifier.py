#!/usr/bin/env python3
"""
Verifier for Sygic GPS 'Enable Speedometer Display' task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enable_speedometer(traj, env_info, task_info):
    """
    Verifies that the agent enabled the speedometer and speed limit display.
    
    Strategy:
    1. Basic checks: App running, screen changed (20 pts)
    2. VLM Verification (80 pts):
       - Did agent go to settings?
       - Are toggles enabled?
       - Is speedometer visible on final map?
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup temp files
    temp_dir = tempfile.mkdtemp()
    result_json_path = os.path.join(temp_dir, "result.json")
    final_ui_path = os.path.join(temp_dir, "final_ui.xml")
    
    score = 0
    feedback_parts = []
    
    try:
        # 1. Fetch JSON result
        try:
            copy_from_env("/sdcard/tasks/enable_speedometer_display/result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to copy result.json: {e}")
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results from device"}

        # 2. Basic Checks (20 points)
        if result.get("app_running", False):
            score += 10
            feedback_parts.append("App is running")
        else:
            feedback_parts.append("App crashed or closed")

        if result.get("screen_changed", False):
            score += 10
            feedback_parts.append("Screen state modified")
        else:
            feedback_parts.append("No visual changes detected")

        # 3. Optional: XML UI Check (Bonus/Confirmation)
        # If the speedometer is a native view, we might see "km/h" or "mph" text
        ui_text_found = False
        try:
            copy_from_env(result.get("final_ui_dump", ""), final_ui_path)
            with open(final_ui_path, 'r', encoding='utf-8', errors='ignore') as f:
                xml_content = f.read().lower()
                if "km/h" in xml_content or "mph" in xml_content or "speed" in xml_content:
                    ui_text_found = True
        except:
            pass # UI dump might fail or file not exist, rely on VLM

        # 4. VLM Verification (80 points)
        # We need to verify the PROCESS (settings) and the OUTCOME (map overlay)
        
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        
        if not final_screen:
            return {"passed": False, "score": score, "feedback": "No screenshots available for verification"}

        prompt = """
        You are verifying a task in Sygic GPS Navigation app.
        The goal is to ENABLE the 'Speedometer' and 'Speed Limit' display on the map.
        
        Please analyze the screenshots (trajectory and final state):
        
        1. SETTINGS NAVIGATION: Did the user navigate to a 'Settings' menu and then to a 'Display', 'View', or 'Navigation' submenu?
        2. TOGGLE ACTIVATION: Can you see the user turning ON toggles related to 'Speedometer', 'Current speed', or 'Speed limit'?
        3. FINAL VERIFICATION: Look at the FINAL screenshot (the last one). Is there a speedometer widget visible on the map? 
           - It usually looks like a small rounded box with a number (likely '0') and units ('km/h' or 'mph').
           - Is there a speed limit sign (circular icon)?
        
        Provide a JSON response:
        {
            "settings_accessed": true/false,
            "toggles_enabled": true/false,
            "speedometer_visible_on_map": true/false,
            "speed_limit_visible_on_map": true/false,
            "confidence": "high/medium/low"
        }
        """
        
        vlm_response = query_vlm(
            images=frames + [final_screen],
            prompt=prompt
        )
        
        vlm_data = vlm_response.get("parsed", {})
        
        # Scoring based on VLM
        if vlm_data.get("settings_accessed", False):
            score += 15
            feedback_parts.append("Settings menu accessed")
            
        if vlm_data.get("toggles_enabled", False):
            score += 25
            feedback_parts.append("Speed toggles enabled")
            
        if vlm_data.get("speedometer_visible_on_map", False):
            score += 30
            feedback_parts.append("Speedometer widget visible on map")
        elif ui_text_found:
            # Fallback if VLM missed it but XML found text
            score += 30
            feedback_parts.append("Speedometer text detected in UI layout")
            
        if vlm_data.get("speed_limit_visible_on_map", False):
            score += 10
            feedback_parts.append("Speed limit indicator visible")

        passed = score >= 70 and (vlm_data.get("speedometer_visible_on_map", False) or ui_text_found)

        return {
            "passed": passed,
            "score": score,
            "feedback": ", ".join(feedback_parts)
        }
        
    finally:
        # Cleanup
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)