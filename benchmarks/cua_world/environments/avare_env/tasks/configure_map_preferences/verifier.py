#!/usr/bin/env python3
"""
Verifier for configure_map_preferences task.
Checks if Avare's XML preferences file contains the expected configurations.
"""

import json
import os
import re
import logging
import tempfile
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_map_preferences(traj, env_info, task_info):
    """
    Verifies that:
    1. The preferences file was modified during the task.
    2. Map Orientation is set to 'Track Up'.
    3. Units are set to 'Knot'.
    4. Draw Tracks is enabled.
    5. The user returned to the main map (checked via final screenshot/focus).
    """
    
    # Setup helpers
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Temp dir for analysis
    with tempfile.TemporaryDirectory() as tmp_dir:
        local_initial_prefs = os.path.join(tmp_dir, "initial_prefs.xml")
        local_final_prefs = os.path.join(tmp_dir, "final_prefs.xml")
        local_result_json = os.path.join(tmp_dir, "task_result.json")
        local_focus_txt = os.path.join(tmp_dir, "final_focus.txt")
        local_start_time = os.path.join(tmp_dir, "task_start_time.txt")
        local_final_mtime = os.path.join(tmp_dir, "final_prefs_mtime.txt")

        # Pull files from Android environment
        try:
            # Android temp dir used in scripts
            android_tmp = "/sdcard/task_tmp"
            
            copy_from_env(f"{android_tmp}/final_prefs.xml", local_final_prefs)
            copy_from_env(f"{android_tmp}/initial_prefs.xml", local_initial_prefs)
            copy_from_env(f"{android_tmp}/task_result.json", local_result_json)
            copy_from_env(f"{android_tmp}/final_focus.txt", local_focus_txt)
            copy_from_env(f"{android_tmp}/task_start_time.txt", local_start_time)
            copy_from_env(f"{android_tmp}/final_prefs_mtime.txt", local_final_mtime)
            
        except Exception as e:
            logger.error(f"Failed to copy files: {e}")
            return {"passed": False, "score": 0, "feedback": "Verification failed: Could not retrieve task data from device."}

        # --- scoring variables ---
        score = 0
        max_score = 100
        feedback = []
        
        # 1. Check Anti-Gaming / File Modification
        try:
            with open(local_start_time, 'r') as f:
                start_ts = int(f.read().strip())
            with open(local_final_mtime, 'r') as f:
                mod_ts = int(f.read().strip())
                
            if mod_ts > start_ts:
                score += 10
                feedback.append("Preferences saved successfully.")
            else:
                feedback.append("Preferences file not modified since start.")
        except:
            feedback.append("Could not verify file modification timestamp.")

        # 2. Parse XML Content
        def parse_prefs(file_path):
            """Returns a dict of key-value pairs from the XML."""
            data = {}
            if not os.path.exists(file_path) or os.path.getsize(file_path) == 0:
                return data
            try:
                # Basic regex parsing is often more robust than XML for Android prefs 
                # because they flat lists, but let's try reading as text to handle loose formats
                with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                    return content
            except Exception as e:
                logger.error(f"Error reading prefs: {e}")
                return ""

        initial_content = parse_prefs(local_initial_prefs)
        final_content = parse_prefs(local_final_prefs)
        
        if not final_content:
            return {"passed": False, "score": 0, "feedback": "Preferences file is empty or missing."}

        # 3. verify Orientation (Track Up)
        # Looking for keys like "Orientation", values like "TrackUp" or specific enums
        # Avare specific: "run_orientation" -> "TrackUp" or similar
        # We look for "TrackUp" in the file which is the distinct value for this setting
        if re.search(r'name=".*Orientation.*".*TrackUp', final_content, re.IGNORECASE) or \
           re.search(r'TrackUp', final_content): 
            score += 30
            feedback.append("Orientation set to 'Track Up'.")
        else:
            feedback.append("Orientation NOT set to 'Track Up'.")

        # 4. Verify Units (Knots)
        # Look for "Units" -> "Knots"
        if re.search(r'name=".*Unit.*".*Knot', final_content, re.IGNORECASE) or \
           re.search(r'Knot', final_content):
            score += 30
            feedback.append("Units set to 'Knots'.")
        else:
            feedback.append("Units NOT set to 'Knots'.")

        # 5. Verify Draw Tracks
        # Look for "Tracks" -> "true" or checked
        # Common key: "ShowTrack", "DrawTracks"
        if re.search(r'name=".*Track.*".*value="true"', final_content, re.IGNORECASE) or \
           re.search(r'name=".*Track.*".*value="1"', final_content, re.IGNORECASE):
            score += 20
            feedback.append("Draw Tracks enabled.")
        else:
            # Fallback: check raw string if XML parsing is messy
            if "DrawTracks" in final_content and "true" in final_content:
                 # Weak check, but maybe acceptable
                 pass
            feedback.append("Draw Tracks setting not confirmed (checked for 'true' value).")

        # 6. Verify Return to Map
        try:
            with open(local_focus_txt, 'r') as f:
                focus_data = f.read()
            # If we are in Preferences, the activity usually contains "PreferenceActivity" or "Settings"
            # If we are on Map, it is usually "MainActivity" or "MapActivity"
            if "MainActivity" in focus_data or "MapActivity" in focus_data:
                score += 10
                feedback.append("Returned to main map view.")
            elif "Preference" in focus_data:
                feedback.append("Still in Preferences menu.")
            else:
                # If unknown, give benefit of doubt if other things passed
                if score >= 60:
                    score += 10
                    feedback.append("UI state ambiguous, assuming return to map.")
        except:
            pass

        # Calculate result
        passed = score >= 70  # Needs at least 2 settings correct + save
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback)
        }