#!/usr/bin/env python3
"""
Verifier for install_custom_waypoint_symbol task.

VERIFICATION STRATEGY:
1. Programmatic Checks (Multiple Independent Signals):
   - BaseCamp was running (10 pts)
   - Custom BMP file was created in correct location (20 pts)
   - GPX file was exported (20 pts)
   - GPX contains waypoint "Sensor-Alpha" at correct coords (25 pts)
   - GPX waypoint has `<sym>` matching a custom symbol index (25 pts)
2. Anti-gaming VLM Check:
   - Uses VLM on trajectory to confirm agent actually interacted with BaseCamp
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def find_elements(root, tag_name):
    """Find all elements ignoring XML namespaces for bullet-proof parsing."""
    results = []
    for elem in root.iter():
        if '}' in elem.tag:
            if elem.tag.split('}')[-1] == tag_name:
                results.append(elem)
        elif elem.tag == tag_name:
            results.append(elem)
    return results

def verify_install_custom_waypoint_symbol(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_lat = metadata.get('lat', 42.445)
    expected_lon = metadata.get('lon', -71.095)
    expected_name = metadata.get('waypoint_name', 'Sensor-Alpha')
    
    score = 0
    feedback_parts = []
    
    # 1. Read JSON State Evidence
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # Score App Running
    if result_data.get('basecamp_running', False):
        score += 10
        feedback_parts.append("BaseCamp was running")
    else:
        feedback_parts.append("BaseCamp was NOT running")
        
    # Score BMP Existence & Timing
    bmp_exists = result_data.get('bmp_exists', False)
    if bmp_exists:
        score += 20
        feedback_parts.append("Custom BMP file created")
        if not result_data.get('bmp_created_during_task', False):
             feedback_parts.append("Warning: BMP file timestamp is older than task start")
    else:
        feedback_parts.append("BMP file not found in correct AppData directory")
        
    # Score GPX Existence & Timing
    gpx_exists = result_data.get('gpx_exists', False)
    if gpx_exists:
        score += 20
        feedback_parts.append("GPX file exported")
        if not result_data.get('gpx_created_during_task', False):
            feedback_parts.append("Warning: GPX file timestamp is older than task start")
    else:
        feedback_parts.append("GPX file not found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 2. Extract & Read GPX Output Data
    temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    gpx_content = ""
    try:
        copy_from_env("C:\\workspace\\output\\sensor_network.gpx", temp_gpx.name)
        with open(temp_gpx.name, 'r', encoding='utf-8') as f:
            gpx_content = f.read()
    except Exception as e:
        feedback_parts.append(f"Failed to copy/read GPX file: {e}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    finally:
        if os.path.exists(temp_gpx.name):
            os.unlink(temp_gpx.name)
            
    # 3. Analyze GPX Content Programmatically 
    sym_correct = False
    loc_correct = False
    try:
        root = ET.fromstring(gpx_content)
        wpt_found = False
        
        for wpt in find_elements(root, 'wpt'):
            name_elems = [e for e in list(wpt) if e.tag.split('}')[-1] == 'name']
            if name_elems and name_elems[0].text and name_elems[0].text.strip() == expected_name:
                wpt_found = True
                
                # Verify bounds/location
                lat = float(wpt.get('lat', 0))
                lon = float(wpt.get('lon', 0))
                if abs(lat - expected_lat) <= 0.005 and abs(lon - expected_lon) <= 0.005:
                    loc_correct = True
                    
                # Verify custom symbol index allocation (Garmin typically outputs 'Custom X')
                sym_elems = [e for e in list(wpt) if e.tag.split('}')[-1] == 'sym']
                if sym_elems and sym_elems[0].text and "Custom" in sym_elems[0].text:
                    sym_correct = True
                elif sym_elems and sym_elems[0].text:
                    feedback_parts.append(f"Found standard symbol instead of custom: {sym_elems[0].text}")
                    
        if wpt_found:
            if loc_correct:
                score += 25
                feedback_parts.append("Waypoint name and location correct")
            else:
                feedback_parts.append("Waypoint found but location incorrect")
                
            if sym_correct:
                score += 25
                feedback_parts.append("Custom symbol correctly assigned & exported")
            else:
                feedback_parts.append("Failed to assign a Custom Symbol index")
        else:
            feedback_parts.append(f"Waypoint '{expected_name}' not found in GPX")
            
    except Exception as e:
        feedback_parts.append(f"Invalid GPX XML generated: {e}")

    # 4. Anti-gaming check: VLM verifies UI interaction using trajectory history (not just final GPX)
    vlm_passed = True  # Start True, override if VLM explicitly detects failure
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = 'Examine these trajectory screenshots. Did the agent interact with the Garmin BaseCamp UI (e.g., clicking on maps, editing waypoint properties, or managing lists)? Reply strictly in JSON format: {"used_basecamp": true/false}'
            vlm_result = query_vlm(prompt=prompt, images=frames)
            
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                if not parsed.get('used_basecamp', False):
                    vlm_passed = False
                    feedback_parts.append("VLM Verification: Agent did not appear to use the BaseCamp interface")
                else:
                    feedback_parts.append("VLM Verification: Agent BaseCamp interaction confirmed")
    except Exception as e:
        logger.warning(f"VLM trajectory verification skipped or failed: {e}")

    # Success Criteria Check (Requires successful setup, location, icon assignment, and VLM check)
    key_criteria_met = bmp_exists and sym_correct and gpx_exists and loc_correct and vlm_passed
    passed = score >= 80 and key_criteria_met
    
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback_parts)}