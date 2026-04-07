#!/usr/bin/env python3
"""
Verifier for Avare Traffic Alert Configuration Task.

Verifies that:
1. The agent navigated the UI (VLM).
2. The specific numeric values (5 and 1500) were saved to the application preferences (XML).
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

def verify_traffic_settings(traj, env_info, task_info):
    """
    Verify traffic alert configuration using Preferences XML and VLM.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_distance = metadata.get('expected_distance', "5")
    expected_height = metadata.get('expected_height', "1500")

    # Temp files for artifacts
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml').name
    
    score = 0
    feedback_parts = []
    
    try:
        # 1. Fetch Result JSON
        try:
            copy_from_env("/sdcard/task_result.json", temp_json)
            with open(temp_json, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

        # 2. Fetch Preferences XML
        prefs_content = ""
        prefs_loaded = False
        if result_data.get("prefs_exists"):
            try:
                copy_from_env("/sdcard/prefs_dump.xml", temp_xml)
                with open(temp_xml, 'r') as f:
                    prefs_content = f.read()
                prefs_loaded = True
            except Exception as e:
                feedback_parts.append(f"Failed to copy prefs file: {str(e)}")

        # --- Verification Logic ---

        # Criterion A: Programmatic Check of Preferences (70 points)
        # We look for keys that hold the traffic values. 
        # Avare keys might be "TrafficWarnDistance", "TrafficWarnHeight" etc.
        # To be robust, we look for entries containing 'Traffic' or 'Warn' with the target values.
        
        dist_set = False
        height_set = False
        
        if prefs_loaded:
            try:
                # Parse XML
                root = ET.fromstring(prefs_content)
                
                # Iterate over all preferences
                for child in root:
                    # Example: <string name="TrafficWarnDistance">5</string>
                    # or <int name="..." value="5" />
                    key = child.get('name', '')
                    value = child.text if child.text else child.get('value', '')
                    
                    if not value: continue
                    value = str(value).strip()

                    # Check Distance
                    # Key usually contains 'Traffic' and 'Distance' or similar
                    if 'Traffic' in key or 'Collision' in key:
                        if value == expected_distance:
                            dist_set = True
                        if value == expected_height:
                            height_set = True
                            
            except ET.ParseError:
                # Fallback to regex if XML parsing fails (e.g. malformed or empty)
                if re.search(r'name="[^"]*Traffic[^"]*".*?>5<', prefs_content) or re.search(r'name="[^"]*Distance[^"]*".*?>5<', prefs_content):
                    dist_set = True
                if re.search(r'name="[^"]*Traffic[^"]*".*?>1500<', prefs_content) or re.search(r'name="[^"]*Height[^"]*".*?>1500<', prefs_content):
                    height_set = True

        if dist_set:
            score += 35
            feedback_parts.append(f"✅ Traffic Warning Distance set to {expected_distance} nm.")
        else:
            feedback_parts.append(f"❌ Traffic Warning Distance NOT found set to {expected_distance}.")

        if height_set:
            score += 35
            feedback_parts.append(f"✅ Traffic Warning Height set to {expected_height} ft.")
        else:
            feedback_parts.append(f"❌ Traffic Warning Height NOT found set to {expected_height}.")

        # Criterion B: VLM Verification of Workflow (30 points)
        # We want to see the agent entering the preferences menu
        frames = sample_trajectory_frames(traj, n=4)
        final_shot = get_final_screenshot(traj)
        
        vlm_prompt = (
            "Analyze these screenshots of an Android aviation app.\n"
            "Did the user:\n"
            "1. Open a 'Preferences' or 'Settings' menu?\n"
            "2. Navigate to 'Traffic', 'Collision', or 'ADS-B' settings?\n"
            "3. Interact with numeric fields for distance or height?\n"
            "Answer with JSON: {\"menu_opened\": bool, \"traffic_settings_seen\": bool, \"values_changed\": bool}"
        )
        
        vlm_result = query_vlm(images=frames + [final_shot], prompt=vlm_prompt)
        vlm_data = vlm_result.get('parsed', {})
        
        if vlm_data.get('menu_opened'):
            score += 10
            feedback_parts.append("✅ Accessed Preferences menu.")
        else:
            feedback_parts.append("⚠️ VLM did not clearly see Preferences menu opening.")

        if vlm_data.get('traffic_settings_seen') or vlm_data.get('values_changed'):
            score += 20
            feedback_parts.append("✅ Interacted with traffic settings UI.")
        else:
            feedback_parts.append("⚠️ VLM did not detect traffic settings interaction.")

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        if os.path.exists(temp_json): os.unlink(temp_json)
        if os.path.exists(temp_xml): os.unlink(temp_xml)

    # Final Pass Determination
    # Must have set BOTH preference values correctly in the backend file to pass
    passed = dist_set and height_set
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }