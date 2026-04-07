#!/usr/bin/env python3
"""
Verifier for configure_distance_rings task.
"""

import json
import os
import sys
import xml.etree.ElementTree as ET
import logging
from typing import Dict, Any

# Adjust path to import gym_anything utilities if needed
# from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_distance_rings(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that Avare distance rings are configured to 5 and 10 NM.
    
    Strategy:
    1. Parse the exported shared_preferences XML file.
    2. Search for keys related to 'Ring', 'Distance', or 'Range'.
    3. Check if values '5' and '10' are assigned to appropriate keys.
    4. (Optional) VLM check on the screenshot to confirm visual feedback.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    # Temp files
    local_result_json = "temp_task_result.json"
    local_prefs_xml = "temp_prefs.xml"
    
    try:
        # 1. Fetch Result JSON
        copy_from_env("/sdcard/tasks/configure_distance_rings/task_result.json", local_result_json)
        
        with open(local_result_json, 'r') as f:
            result_data = json.load(f)
            
        # 2. Fetch Preferences XML
        remote_xml_path = result_data.get("prefs_file_path")
        if remote_xml_path and result_data.get("prefs_file_exists"):
            copy_from_env(remote_xml_path, local_prefs_xml)
        else:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Preferences file not found on device. Did the app run?"
            }

        # 3. Analyze XML
        score = 0
        feedback = []
        
        try:
            tree = ET.parse(local_prefs_xml)
            root = tree.getroot()
            
            # Convert XML to a dict for easier searching
            # SharedPreferences usually look like: <string name="key">value</string> or <int name="key" value="123" />
            prefs = {}
            for child in root:
                key = child.attrib.get('name')
                
                # Value can be in 'value' attrib (int/bool) or text (string)
                val = child.attrib.get('value')
                if val is None:
                    val = child.text
                
                if key:
                    prefs[key] = str(val)

            # Heuristic Search for Ring Settings
            # We don't know the EXACT internal variable names without source code, 
            # so we look for likely candidates containing "Ring", "Dist", "Range" AND having values "5" or "10".
            
            found_5 = False
            found_10 = False
            
            # Common patterns for distance ring keys in apps
            likely_keys = [k for k in prefs.keys() if any(x in k.lower() for x in ['ring', 'dist', 'range'])]
            
            logger.info(f"Found likely preference keys: {likely_keys}")
            
            for k in likely_keys:
                val = prefs[k]
                if val == "5" or val == "5.0":
                    found_5 = True
                    feedback.append(f"Found Inner Ring setting: {k} = {val}")
                if val == "10" or val == "10.0":
                    found_10 = True
                    feedback.append(f"Found Outer Ring setting: {k} = {val}")

            # Scoring based on preferences
            if found_5:
                score += 40
            else:
                feedback.append("Missing setting for 5 NM.")
                
            if found_10:
                score += 40
            else:
                feedback.append("Missing setting for 10 NM.")
                
            # Anti-gaming: Check if any "Ring" related key exists at all (implies app was at least initialized)
            if not likely_keys:
                feedback.append("No distance/ring settings found in preferences. App state might be clean/default.")

        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to parse preferences XML: {str(e)}"}

        # 4. VLM Verification (Visual Check)
        # Using the prompt pattern from examples
        query_vlm = env_info.get('query_vlm')
        if query_vlm and score >= 40: # Only bother check visual if at least one setting was found
            
            # Get screenshot from trajectory or final export
            # We will use the exported one to ensure it matches the end state
            local_screenshot = "temp_final_screenshot.png"
            remote_screenshot = result_data.get("final_screenshot_path")
            
            if remote_screenshot:
                copy_from_env(remote_screenshot, local_screenshot)
                
                vlm_prompt = """
                You are verifying an aviation app task.
                Look at the map screen.
                1. Do you see concentric circles (rings) centered on the aircraft/location cursor?
                2. Are there exactly two distinct rings visible (or labels indicating 5 and 10)?
                3. Does the interface look like a map view?
                
                Return JSON: {"rings_visible": bool, "map_view": bool}
                """
                
                vlm_result = query_vlm(image=local_screenshot, prompt=vlm_prompt)
                
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("rings_visible") and parsed.get("map_view"):
                        score += 20
                        feedback.append("Visual verification passed: Rings visible on map.")
                    else:
                        feedback.append("Visual verification failed: Rings not clearly visible.")
                
                if os.path.exists(local_screenshot):
                    os.unlink(local_screenshot)

        # Final Cleanup and Result
        passed = (score >= 80) # Require both settings (40+40) or one setting + visual (40+20 is low, strict 80 implies both settings correct)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        for f in [local_result_json, local_prefs_xml]:
            if os.path.exists(f):
                os.unlink(f)