#!/usr/bin/env python3
"""
Verifier for configure_fuel_tank_timer task.

Verification Logic:
1. Primary: VLM analysis of the final screenshot to confirm the "Fuel Timer" or "30:00" is visible on the dashboard.
2. Secondary: Programmatic check of Avare's XML preferences file to confirm the setting was saved.
"""

import json
import os
import tempfile
import logging
import re
from typing import Dict, Any

# Import VLM utilities from the framework
from gym_anything.vlm import query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fuel_tank_timer(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    # Setup temporary files
    temp_dir = tempfile.mkdtemp()
    local_result_json = os.path.join(temp_dir, "task_result.json")
    local_screenshot = os.path.join(temp_dir, "task_final.png")
    local_prefs = os.path.join(temp_dir, "avare_preferences.xml")

    score = 0
    feedback = []
    
    try:
        # 1. Retrieve Result JSON
        try:
            copy_from_env("/sdcard/task_result.json", local_result_json)
            with open(local_result_json, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task metadata: {str(e)}"}

        # 2. Retrieve Screenshot for VLM
        has_screenshot = False
        try:
            copy_from_env("/sdcard/task_final.png", local_screenshot)
            if os.path.getsize(local_screenshot) > 0:
                has_screenshot = True
        except Exception:
            feedback.append("Warning: Could not retrieve final screenshot.")

        # 3. Retrieve Preferences XML
        has_prefs = False
        try:
            if result_data.get("prefs_exported"):
                copy_from_env("/sdcard/avare_preferences.xml", local_prefs)
                if os.path.exists(local_prefs):
                    has_prefs = True
        except Exception:
            feedback.append("Warning: Could not retrieve preferences file.")

        # --- EVALUATION ---

        # Criterion A: Preferences Check (40 points)
        # We look for the specific value "FuelTimer" in the XML.
        # Avare typically saves dashboard fields with values like "FuelTimer".
        pref_score = 0
        if has_prefs:
            try:
                with open(local_prefs, 'r', encoding='utf-8', errors='ignore') as f:
                    xml_content = f.read()
                    # Check for "FuelTimer" which is the internal class name/tag usually used
                    if "FuelTimer" in xml_content:
                        pref_score = 40
                        feedback.append("Programmatic Check Passed: 'FuelTimer' setting found in preferences.")
                    else:
                        feedback.append("Programmatic Check Failed: 'FuelTimer' not found in preferences file.")
            except Exception as e:
                feedback.append(f"Error reading preferences: {e}")
        else:
            feedback.append("Skipping preferences check (file missing).")
        
        score += pref_score

        # Criterion B: VLM Visual Verification (60 points)
        # This is the primary check because it proves it's actually displayed to the user.
        vlm_score = 0
        if has_screenshot:
            prompt = (
                "You are an aviation app verifier. Look at this screenshot of the Avare GPS app. "
                "The user was asked to configure a 'Fuel Tank Switch Timer' on the dashboard. "
                "The dashboard consists of text fields at the very top or bottom of the map view. "
                "Do you see a field displaying '30:00' (the default timer start), 'Fuel', 'Timer', or 'Switch'? "
                "Return JSON with keys: {'timer_visible': boolean, 'text_seen': string}."
            )
            
            try:
                # Assuming query_vlm handles the image loading from path
                vlm_response = query_vlm(
                    prompt=prompt,
                    images=[local_screenshot]
                )
                
                # Check VLM result
                if vlm_response.get("success"):
                    parsed = vlm_response.get("parsed", {})
                    if parsed.get("timer_visible"):
                        vlm_score = 60
                        feedback.append(f"Visual Check Passed: VLM detected timer ({parsed.get('text_seen', 'unknown text')}).")
                    else:
                        feedback.append("Visual Check Failed: VLM did not see the fuel timer on the screen.")
                else:
                    feedback.append("Visual Check Error: VLM failed to process image.")
            except Exception as e:
                feedback.append(f"Visual Check Error: {str(e)}")
        else:
            feedback.append("Visual Check Failed: No screenshot available.")

        score += vlm_score

        # Final Pass/Fail Determination
        # We require at least one strong signal (visual or prefs), but visual is preferred.
        # Threshold: 60. This means Visual alone (60) passes, Prefs alone (40) fails.
        # This enforces that the user actually sees the result.
        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback)
        }

    finally:
        # Cleanup
        try:
            import shutil
            shutil.rmtree(temp_dir)
        except:
            pass