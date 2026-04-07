#!/usr/bin/env python3
"""
Verifier for enable_airspace_alerts task.

Verifies that:
1. The Avare preferences file contains an enabled setting for Airspace Warnings.
2. The preferences file was modified AFTER the task started (anti-gaming).
3. (Optional) VLM confirms the settings screen was accessed.
"""

import json
import os
import tempfile
import logging
import re
from xml.etree import ElementTree

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enable_airspace_alerts(traj, env_info, task_info):
    """
    Verify that Airspace Warnings are enabled in Avare preferences.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # Setup temp files
    temp_dir = tempfile.mkdtemp()
    local_result_json = os.path.join(temp_dir, "result.json")
    local_prefs_xml = os.path.join(temp_dir, "preferences.xml")
    
    try:
        # 1. Fetch Result JSON
        try:
            copy_from_env("/sdcard/task_results/result.json", local_result_json)
            with open(local_result_json, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

        # 2. Fetch Preferences XML
        prefs_exists = result_data.get("prefs_file_exists", False)
        if prefs_exists:
            try:
                copy_from_env("/sdcard/task_results/preferences.xml", local_prefs_xml)
            except Exception as e:
                feedback_parts.append("Could not retrieve preferences file despite report saying it exists.")
                prefs_exists = False
        
        # === CRITERION 1: Preference Analysis (50 pts) ===
        airspace_enabled = False
        key_found = None
        
        if prefs_exists and os.path.exists(local_prefs_xml):
            try:
                # Read file content directly to handle potential XML parsing issues gracefully
                with open(local_prefs_xml, 'r') as f:
                    content = f.read()
                
                # Avare specific keys for Airspace/Alarms
                # We look for boolean entries set to true with relevant names
                # Example: <boolean name="AirspaceAlarm" value="true" />
                
                # Regex for flexibility across versions
                # Matches <boolean name="...Airspace..." value="true" />
                # or <boolean name="...Alarm..." value="true" />
                airspace_regex = r'<boolean name="[^"]*(Airspace|Alarm)[^"]*" value="true"'
                match = re.search(airspace_regex, content, re.IGNORECASE)
                
                if match:
                    airspace_enabled = True
                    key_found = match.group(0)
                    score += 50
                    feedback_parts.append(f"Airspace preference enabled (found key matching pattern)")
                else:
                    feedback_parts.append("Airspace preference NOT enabled in settings file")
                    
            except Exception as e:
                feedback_parts.append(f"Error parsing preferences XML: {str(e)}")
        else:
            feedback_parts.append("Preferences file missing")

        # === CRITERION 2: Anti-Gaming Timestamp Check (20 pts) ===
        start_time = result_data.get("task_start_time", 0)
        mod_time = result_data.get("prefs_mod_time", 0)
        
        # Allow a small buffer, but mod_time should generally be > start_time
        # If mod_time is 0, file wasn't found or stat failed
        if mod_time > start_time:
            score += 20
            feedback_parts.append("Settings modified during task execution")
        elif mod_time > 0:
            feedback_parts.append("Settings NOT modified during task (timestamp too old)")
            # If the setting was already enabled and they didn't touch it, they fail this check
            # The setup script specifically disables it, so this implies they didn't do the work
        else:
            feedback_parts.append("Could not verify file modification time")

        # === CRITERION 3: UI Navigation (VLM) (30 pts) ===
        # We check if the agent visited the Preferences screen
        # This is a fallback/supplement to the file check
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        frames = sample_trajectory_frames(traj, n=8)
        
        vlm_prompt = """
        Review these screenshots from an Android aviation app (Avare).
        Did the user navigate to the 'Preferences' or 'Settings' screen?
        Look for a menu with options like 'Preferences', 'General', 'Display', 'Alerts', 'Airspace'.
        
        Return JSON:
        {
            "preferences_opened": true/false,
            "airspace_setting_visible": true/false,
            "reasoning": "..."
        }
        """
        
        try:
            vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
            vlm_data = vlm_result.get('parsed', {})
            
            if vlm_data.get('preferences_opened', False):
                score += 30
                feedback_parts.append("Verified navigation to Preferences")
            else:
                feedback_parts.append("VLM did not detect Preferences screen")
                
        except Exception as e:
            # If VLM fails, we rely on file check but cap score if file check was weak
            logger.warning(f"VLM check failed: {e}")
            feedback_parts.append("Visual verification skipped due to error")
            if airspace_enabled:
                score += 10 # Give partial credit if file is correct

        # Final Success Logic
        # Must have enabled the setting AND modified the file
        passed = airspace_enabled and (mod_time > start_time)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    finally:
        # Cleanup
        if os.path.exists(temp_dir):
            import shutil
            shutil.rmtree(temp_dir)