#!/usr/bin/env python3
"""
Verifier for enable_auto_diagram task (Avare GPS).

Verification Logic:
1. Retrieve the exported preferences XML file from the environment.
2. Parse the XML to find the boolean key for "Auto Show Airport Diagram".
3. Verify the value is set to "true".
4. Verify the file was modified after task start (anti-gaming).
5. Verify the agent returned to the map view (via VLM or UI state).
"""

import json
import os
import tempfile
import logging
import re
import xml.etree.ElementTree as ET
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enable_auto_diagram(traj, env_info, task_info):
    """
    Verify that the 'Auto Show Airport Diagram' preference was enabled.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup paths
    result_json_path = "/sdcard/task_result.json"
    prefs_xml_path = "/sdcard/final_preferences.xml"
    
    # Temp file management
    temp_dir = tempfile.mkdtemp()
    local_result_json = os.path.join(temp_dir, "task_result.json")
    local_prefs_xml = os.path.join(temp_dir, "prefs.xml")
    
    score = 0
    feedback_parts = []
    
    try:
        # 1. Load result metadata
        try:
            copy_from_env(result_json_path, local_result_json)
            with open(local_result_json, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}

        # 2. Retrieve Preferences XML
        prefs_available = False
        try:
            copy_from_env(prefs_xml_path, local_prefs_xml)
            if os.path.getsize(local_prefs_xml) > 0:
                prefs_available = True
        except Exception:
            feedback_parts.append("Could not retrieve preferences file.")

        # --- CRITERION 1: Preferences File Modification (20 pts) ---
        if result_data.get("prefs_file_modified", False) and prefs_available:
            score += 20
            feedback_parts.append("Preferences updated.")
        else:
            feedback_parts.append("Preferences file NOT modified (did you change any settings?).")

        # --- CRITERION 2: Feature Enabled (60 pts) ---
        feature_enabled = False
        if prefs_available:
            try:
                tree = ET.parse(local_prefs_xml)
                root = tree.getroot()
                
                # Look for key matching *AirportDiagram* or *ShowDiagram*
                # Common pattern in Avare: "ShowAirportDiagram"
                found_key = False
                for child in root.findall('boolean'):
                    name = child.get('name', '')
                    value = child.get('value', 'false')
                    
                    if 'AirportDiagram' in name or ('Show' in name and 'Diagram' in name):
                        found_key = True
                        if value.lower() == 'true':
                            feature_enabled = True
                            score += 60
                            feedback_parts.append(f"Setting '{name}' is enabled.")
                            break
                        else:
                            feedback_parts.append(f"Setting '{name}' found but value is '{value}' (expected true).")
                
                if not found_key:
                    feedback_parts.append("Could not locate specific 'Airport Diagram' preference key in file.")
                    
            except ET.ParseError:
                feedback_parts.append("Failed to parse preferences XML.")

        # --- CRITERION 3: Return to Map / UI State (20 pts) ---
        # We combine the script's focus check with a quick VLM check for robustness
        returned_to_map = result_data.get("returned_to_map", False)
        
        # Verify visually
        final_screenshot = get_final_screenshot(traj)
        vlm_check = False
        if final_screenshot:
            vlm_response = query_vlm(
                prompt="Is this the main map view of an aviation app? Look for a map, aviation charts, or aircraft position icon. Answer yes or no.",
                image=final_screenshot
            )
            if vlm_response.get("success") and "yes" in vlm_response.get("result", "").lower():
                vlm_check = True
        
        if returned_to_map or vlm_check:
            score += 20
            feedback_parts.append("Returned to main map view.")
        else:
            feedback_parts.append("Did not return to the main map screen.")

    finally:
        # Cleanup
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)

    passed = (score >= 80) and feature_enabled
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }