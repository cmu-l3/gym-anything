#!/usr/bin/env python3
"""
Verifier for set_waypoint_proximity_alerts task.

HYBRID VERIFICATION STRATEGY:
1. Programmatic: GPX file parsing to verify the exact <proximity> XML nodes
2. Anti-Gaming: Geographic bounds check and modification timestamps
3. Visual: VLM verification of trajectory frames showing UI interaction
"""

import json
import os
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_set_waypoint_proximity_alerts(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Fetch Task Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("C:\\temp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Base Validation
    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    gpx_path = result.get('gpx_path', "C:\\Users\\Docker\\Documents\\fells_proximity_alerts.gpx")

    if output_exists:
        score += 10
        feedback_parts.append("GPX file exists")
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Exported GPX file not found at expected path.",
            "details": {"output_exists": False}
        }

    if file_created_during_task:
        score += 5
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("Warning: File timestamp indicates it might be spoofed")

    # 3. Read GPX file
    temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    gpx_content = ""
    try:
        copy_from_env(gpx_path, temp_gpx.name)
        with open(temp_gpx.name, 'r', encoding='utf-8', errors='ignore') as f:
            gpx_content = f.read()
    except Exception as e:
        logger.error(f"Failed to copy/read GPX: {e}")
        feedback_parts.append("Failed to read GPX file")
    finally:
        if os.path.exists(temp_gpx.name):
            os.unlink(temp_gpx.name)

    if not gpx_content:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + " | GPX file is empty or unreadable"
        }

    # 4. Parse GPX to verify proximity nodes
    prox_count = 0
    
    try:
        root = ET.fromstring(gpx_content)
        score += 10
        feedback_parts.append("Valid XML")
        
        # Traverse and find all <wpt> elements ignoring namespaces
        wpts = [elem for elem in root.iter() if elem.tag.endswith('wpt')]
        
        if wpts:
            # ANTI-GAMING: Check geographic location to ensure they used the REAL Fells dataset
            lat = float(wpts[0].get('lat', 0))
            lon = float(wpts[0].get('lon', 0))
            if 42.4 < lat < 42.5 and -71.15 < lon < -71.05:
                score += 5
                feedback_parts.append("Coordinates match Fells region")
            else:
                feedback_parts.append(f"Coordinates outside expected region ({lat}, {lon})")
            
            # Count how many waypoints have proximity set to ~200m
            for wpt in wpts:
                prox_val = None
                # Account for standard and extended Garmin tags (ignoring namespace)
                for child in wpt.iter():
                    if child.tag.lower().endswith('proximity'):
                        prox_val = child.text
                        break
                
                if prox_val is not None:
                    try:
                        val = float(prox_val)
                        if 195 <= val <= 205:  # Tolerance around 200m
                            prox_count += 1
                    except ValueError:
                        pass
        else:
            feedback_parts.append("No waypoints found in GPX")
            
    except ET.ParseError:
        feedback_parts.append("GPX file is not valid XML")
    
    # 5. Award Points for accurate value configurations
    if prox_count >= 1:
        score += 25
        feedback_parts.append("Proximity 200m set on >=1 waypoint")
    if prox_count >= 2:
        score += 20
        feedback_parts.append("Proximity 200m set on >=2 waypoints")
    if prox_count >= 3:
        score += 10
        feedback_parts.append("Proximity 200m set on >=3 waypoints")

    # 6. Secondary Verification: Visual VLM Trajectory Check
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        images = frames
        if final:
            images.append(final)
            
        if images:
            prompt = """You are analyzing screenshots of an agent using Garmin BaseCamp.
Did the agent open the Waypoint Properties dialog to edit the 'Proximity' field, AND did it open the Export dialog to save the file?
Return a JSON object:
{
    "properties_dialog_opened": true/false,
    "proximity_edited": true/false,
    "export_dialog_opened": true/false
}"""
            vlm_resp = query_vlm(images=images, prompt=prompt)
            
            # Robust JSON/Text response parser
            if isinstance(vlm_resp, dict) and 'parsed' in vlm_resp:
                parsed = vlm_resp['parsed']
                if parsed.get('properties_dialog_opened'):
                    score += 8
                    feedback_parts.append("VLM: Properties dialog opened")
                if parsed.get('proximity_edited'):
                    score += 5
                    feedback_parts.append("VLM: Proximity edited")
                if parsed.get('export_dialog_opened'):
                    score += 2
                    feedback_parts.append("VLM: Export dialog opened")
            else:
                resp_str = str(vlm_resp).lower()
                if "true" in resp_str and "properties_dialog" in resp_str:
                    score += 8
                    feedback_parts.append("VLM: Properties dialog opened")
                if "true" in resp_str and "proximity" in resp_str:
                    score += 5
                    feedback_parts.append("VLM: Proximity edited")
                if "true" in resp_str and "export" in resp_str:
                    score += 2
                    feedback_parts.append("VLM: Export dialog opened")
                    
    except Exception as e:
        logger.warning(f"VLM verification skipped/failed: {e}")
        # Partial credit if programmatic passed perfectly but VLM failed technically
        if prox_count >= 1:
            score += 15
            feedback_parts.append("VLM check skipped, inferred visual interaction via file outputs")

    # Final logic
    passed = score >= 55 and prox_count >= 1
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }