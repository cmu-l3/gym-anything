#!/usr/bin/env python3
"""
Verifier for configure_adsb_receiver task.

Criteria:
1. SharedPreferences XML must contain correct IP (192.168.10.1) and Port (4000).
2. Preferences must have been modified AFTER task start.
3. User-created config file must exist and contain correct values.
4. VLM verification of trajectory (UI navigation).
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

def verify_configure_adsb_receiver(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_ip = metadata.get('expected_ip', '192.168.10.1')
    expected_port = metadata.get('expected_port', '4000')

    # Temporary files for extraction
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_prefs = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')

    score = 0
    feedback_parts = []
    
    try:
        # 1. Fetch Task Result JSON
        try:
            copy_from_env("/sdcard/task_result.json", temp_json.name)
            with open(temp_json.name, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}

        task_start = result_data.get('task_start', 0)
        prefs_mtime = result_data.get('prefs_mtime', 0)

        # 2. Analyze SharedPreferences (Primary Ground Truth)
        prefs_valid = False
        ip_found = False
        port_found = False
        
        if result_data.get('prefs_exists'):
            try:
                copy_from_env("/sdcard/final_prefs.xml", temp_prefs.name)
                
                # Check modification time
                if int(prefs_mtime) > int(task_start):
                    score += 10
                    feedback_parts.append("Settings modified during task (+10)")
                else:
                    feedback_parts.append("Warning: Settings file not modified during task session")

                # Parse XML
                # Format is usually <map><string name="pref_key">value</string>...</map>
                tree = ET.parse(temp_prefs.name)
                root = tree.getroot()
                
                # Avare specific keys might vary, so we search all values first or look for standard patterns
                # Common Avare keys: "WIFI_PORT", "WIFI_IP", etc.
                
                all_text_values = []
                for elem in root.iter():
                    if elem.text:
                        all_text_values.append(elem.text)
                    if 'value' in elem.attrib:
                        all_text_values.append(elem.attrib['value'])
                
                # Check IP
                if expected_ip in all_text_values:
                    ip_found = True
                    score += 30
                    feedback_parts.append(f"Correct IP {expected_ip} found in preferences (+30)")
                else:
                    feedback_parts.append(f"IP {expected_ip} NOT found in preferences")

                # Check Port
                if expected_port in all_text_values:
                    port_found = True
                    score += 30
                    feedback_parts.append(f"Correct Port {expected_port} found in preferences (+30)")
                else:
                    feedback_parts.append(f"Port {expected_port} NOT found in preferences")
                    
            except Exception as e:
                feedback_parts.append(f"Error parsing preferences XML: {str(e)}")

        # 3. Analyze Output File (Agent created)
        if result_data.get('output_exists'):
            try:
                copy_from_env("/sdcard/adsb_config.txt", temp_output.name)
                with open(temp_output.name, 'r') as f:
                    content = f.read()
                    
                file_score = 0
                if expected_ip in content:
                    file_score += 5
                if expected_port in content:
                    file_score += 5
                
                if file_score == 10:
                    score += 10
                    feedback_parts.append("Output confirmation file correct (+10)")
                elif file_score > 0:
                    score += 5
                    feedback_parts.append("Output confirmation file partially correct (+5)")
                else:
                    feedback_parts.append("Output file content incorrect")
            except Exception:
                feedback_parts.append("Failed to read output file")
        else:
            feedback_parts.append("Output config file not created")

        # 4. VLM Trajectory Verification
        # We want to see the agent navigating menus, not just magic file edits
        frames = sample_trajectory_frames(traj, n=5)
        final_screenshot = get_final_screenshot(traj)
        
        vlm_prompt = """
        Review these screenshots of an agent using the Avare aviation app.
        Did the agent navigate to the 'Preferences' or 'Settings' menu?
        Did they access a 'Weather', 'Traffic', or 'ADS-B' section?
        Did they enter network settings (IP/Port)?
        
        Return JSON: {"navigated_settings": bool, "accessed_network_config": bool, "reason": str}
        """
        
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        vlm_score = 0
        if vlm_result.get('success'):
            parsed = vlm_result.get('parsed', {})
            if parsed.get('navigated_settings'):
                vlm_score += 10
            if parsed.get('accessed_network_config'):
                vlm_score += 10
            feedback_parts.append(f"VLM Analysis: {parsed.get('reason', 'N/A')}")
        
        score += vlm_score
        if vlm_score > 0:
            feedback_parts.append(f"Visual verification passed (+{vlm_score})")

    finally:
        # Cleanup
        for fpath in [temp_json.name, temp_prefs.name, temp_output.name]:
            if os.path.exists(fpath):
                os.unlink(fpath)

    passed = score >= 60 and ip_found and port_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }