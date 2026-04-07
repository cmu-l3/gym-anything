#!/usr/bin/env python3
"""
Verifier for enable_sharp_curve_warnings task.

Verification Logic:
1. XML Config Verification (Primary):
   - Scans the exported Sygic preference XML files.
   - Looks for a boolean key containing "curve" (e.g., "warning_sharp_curve").
   - Verifies the value is "true".
2. VLM Verification (Secondary):
   - Analyzes trajectory screenshots to confirm the agent navigated to "Notifications"
   - Confirms the "Sharp curve" toggle is visually ON in the final state.
"""

import json
import os
import tarfile
import tempfile
import xml.etree.ElementTree as ET
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sharp_curve_warnings(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Setup temp directory for analysis
    with tempfile.TemporaryDirectory() as temp_dir:
        # ---------------------------------------------------------
        # 1. Fetch Data
        # ---------------------------------------------------------
        result_json_path = os.path.join(temp_dir, "result.json")
        prefs_local_dir = os.path.join(temp_dir, "prefs")
        os.makedirs(prefs_local_dir, exist_ok=True)
        
        try:
            # Copy result JSON
            copy_from_env("/sdcard/tasks/enable_sharp_curve_warnings/result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result_data = json.load(f)
            
            # Copy all XML prefs (files might be numerous, so we list or try common names)
            # Since we can't glob with copy_from_env easily, we assume the export script
            # copied them to a predictable folder. We'll try to copy the main prefs file.
            # The export script put them in /sdcard/tasks/enable_sharp_curve_warnings/final_prefs/
            # We will try to copy the most likely file: com.sygic.aura_preferences.xml
            remote_prefs_path = "/sdcard/tasks/enable_sharp_curve_warnings/final_prefs/com.sygic.aura_preferences.xml"
            local_prefs_path = os.path.join(prefs_local_dir, "com.sygic.aura_preferences.xml")
            
            try:
                copy_from_env(remote_prefs_path, local_prefs_path)
                prefs_available = True
            except Exception:
                logger.warning(f"Could not copy specific prefs file {remote_prefs_path}")
                prefs_available = False

        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task data: {str(e)}"}

        # ---------------------------------------------------------
        # 2. Preference File Analysis (40 points)
        # ---------------------------------------------------------
        score = 0
        feedback = []
        curve_setting_found = False
        curve_setting_enabled = False

        if prefs_available and os.path.exists(local_prefs_path):
            try:
                tree = ET.parse(local_prefs_path)
                root = tree.getroot()
                
                # Search for relevant keys
                # We look for keys like "warning", "curve", "safety"
                for child in root:
                    name = child.get('name', '').lower()
                    value = child.get('value', '').lower()
                    
                    # Heuristic for the key
                    if 'curve' in name and 'warning' in name:
                        curve_setting_found = True
                        if value == 'true':
                            curve_setting_enabled = True
                            feedback.append(f"Found enabled setting: {name}")
                        else:
                            feedback.append(f"Found setting {name} but it was disabled")
            except Exception as e:
                feedback.append(f"XML parsing error: {e}")
        
        if curve_setting_enabled:
            score += 40
        elif curve_setting_found:
            score += 10 # Found key but wrong value
            feedback.append("Sharp curve setting was located but not enabled in config files.")
        else:
            feedback.append("Could not locate specific sharp curve setting in configuration files.")

        # ---------------------------------------------------------
        # 3. VLM Trajectory Verification (60 points)
        # ---------------------------------------------------------
        # We rely heavily on VLM because config keys can be obscure/hashed
        
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        
        prompt = """
        Review this sequence of screenshots from a GPS navigation app.
        The user's goal is to enable "Sharp curve warnings" in the Settings.
        
        Please verify:
        1. Did the user navigate to a Settings or Notifications menu?
        2. Is there a "Sharp curve", "Curves", or similar warning option visible?
        3. In the final state, is the toggle switch for this option ON (usually colored/highlighted) or OFF (gray)?
        
        Return JSON:
        {
            "settings_accessed": boolean,
            "curve_option_visible": boolean,
            "final_toggle_state_on": boolean,
            "confidence": float (0-1)
        }
        """
        
        vlm_response = query_vlm(
            images=frames + [final_screen],
            prompt=prompt
        )
        
        vlm_passed = False
        if vlm_response.get('success'):
            parsed = vlm_response.get('parsed', {})
            
            if parsed.get('settings_accessed'):
                score += 10
            
            if parsed.get('curve_option_visible'):
                score += 20
                
            if parsed.get('final_toggle_state_on'):
                score += 30
                vlm_passed = True
                feedback.append("Visual verification confirmed 'Sharp curve' warning is enabled.")
            else:
                feedback.append("Visual verification did NOT see the toggle enabled.")
        else:
            feedback.append("VLM analysis failed.")

        # ---------------------------------------------------------
        # 4. Final Scoring
        # ---------------------------------------------------------
        # Pass if: (Config confirmed enabled) OR (VLM confirmed enabled AND config found key)
        # We allow VLM alone to pass if config was missing/unreadable, provided score is high
        
        passed = False
        if score >= 90:
            passed = True
        elif score >= 60 and (curve_setting_enabled or vlm_passed):
            passed = True
            
        return {
            "passed": passed,
            "score": min(100, score),
            "feedback": " ".join(feedback)
        }