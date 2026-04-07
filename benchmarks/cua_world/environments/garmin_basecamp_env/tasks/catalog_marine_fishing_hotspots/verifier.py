#!/usr/bin/env python3
"""
Verifier for the catalog_marine_fishing_hotspots task.
Verifies the GPX file creation, waypoint attributes, coordinate accuracy,
and embedded Garmin metadata extensions (Depth and Temperature).
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    HAS_VLM = True
except ImportError:
    HAS_VLM = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def strip_ns(tag):
    """Strip XML namespaces to simplify parsing."""
    if '}' in tag:
        return tag.split('}')[1]
    return tag

def parse_gpx_waypoints(gpx_content):
    """Parse GPX XML content and extract waypoints with their extensions."""
    waypoints = {}
    try:
        root = ET.fromstring(gpx_content)
        for elem in root.iter():
            tag = strip_ns(elem.tag)
            if tag == 'wpt':
                lat = float(elem.attrib.get('lat', 0))
                lon = float(elem.attrib.get('lon', 0))
                name, sym = "", ""
                depth, temp = None, None
                
                # Iterate children of wpt
                for child in elem.iter():
                    ctag = strip_ns(child.tag)
                    if ctag == 'name':
                        name = child.text if child.text else ""
                    elif ctag == 'sym':
                        sym = child.text if child.text else ""
                    elif ctag == 'Depth':
                        try:
                            depth = float(child.text)
                        except (ValueError, TypeError):
                            pass
                    elif ctag == 'Temperature':
                        try:
                            temp = float(child.text)
                        except (ValueError, TypeError):
                            pass
                
                if name:
                    waypoints[name.strip()] = {
                        'lat': lat,
                        'lon': lon,
                        'sym': sym.strip(),
                        'depth': depth,
                        'temp': temp
                    }
    except ET.ParseError as e:
        logger.error(f"Failed to parse GPX XML: {e}")
    return waypoints

def verify_catalog_marine_fishing_hotspots(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_waypoints = metadata.get('waypoints', [])
    coord_tolerance = metadata.get('coord_tolerance', 0.005)
    value_tolerance = metadata.get('value_tolerance', 0.5)

    score = 0
    feedback_parts = []
    
    # 1. Read task_result.json
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export JSON: {e}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    # Validate output file presence
    if not result_data.get('output_exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output GPX file not found. Ensure you exported the data to the correct path."
        }
    
    if result_data.get('file_created_during_task', False):
        score += 10
        feedback_parts.append("File exported during task")
    else:
        feedback_parts.append("Warning: Output file exists but appears to be stale")

    # 2. Read GPX File
    temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    waypoints = {}
    try:
        copy_from_env("C:\\workspace\\output\\fishing_hotspots.gpx", temp_gpx.name)
        with open(temp_gpx.name, 'r', encoding='utf-8') as f:
            gpx_content = f.read()
            waypoints = parse_gpx_waypoints(gpx_content)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": "Failed to read or parse the GPX file"}
    finally:
        if os.path.exists(temp_gpx.name):
            os.unlink(temp_gpx.name)

    if not waypoints:
        return {"passed": False, "score": score, "feedback": "GPX file contains no readable waypoints"}

    # Track sub-scores
    names_matched = 0
    coords_correct = 0
    syms_correct = 0
    depths_correct = 0
    temps_correct = 0
    total_expected = len(expected_waypoints)

    for expected in expected_waypoints:
        wpt_name = expected['name']
        if wpt_name in waypoints:
            names_matched += 1
            actual = waypoints[wpt_name]
            
            # Check Coordinates
            if (abs(actual['lat'] - expected['lat']) <= coord_tolerance and 
                abs(actual['lon'] - expected['lon']) <= coord_tolerance):
                coords_correct += 1
                
            # Check Symbology
            if actual['sym'] in (expected['symbol'], expected['alt_symbol']):
                syms_correct += 1
                
            # Check Depth
            if actual['depth'] is not None and abs(actual['depth'] - expected['depth']) <= value_tolerance:
                depths_correct += 1
                
            # Check Temp
            if actual['temp'] is not None and abs(actual['temp'] - expected['temperature']) <= value_tolerance:
                temps_correct += 1

    # Assign Points based on matches
    # Names present: up to 15
    score += int((names_matched / total_expected) * 15)
    # Coordinates: up to 15
    score += int((coords_correct / total_expected) * 15)
    # Symbology: up to 15
    score += int((syms_correct / total_expected) * 15)
    # Depth: up to 20
    score += int((depths_correct / total_expected) * 20)
    # Temp: up to 15
    score += int((temps_correct / total_expected) * 15)

    feedback_parts.append(f"Found {names_matched}/{total_expected} expected waypoints")
    feedback_parts.append(f"{coords_correct}/{total_expected} coords accurate")
    feedback_parts.append(f"{syms_correct}/{total_expected} symbols correct")
    feedback_parts.append(f"{depths_correct}/{total_expected} depth values correct")
    feedback_parts.append(f"{temps_correct}/{total_expected} temp values correct")

    # 3. VLM Verification for Process (10 points)
    vlm_points = 0
    if HAS_VLM and 'query_vlm' in globals():
        try:
            frames = sample_trajectory_frames(traj, n=5)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                prompt = """You are evaluating a user interacting with Garmin BaseCamp desktop application.
                Look at the provided trajectory screenshots and determine if the user successfully opened the 'Waypoint Properties' dialog window at any point to manually enter data like Depth, Temperature, or Symbol. 
                
                Respond in JSON format:
                {
                    "properties_dialog_used": true/false,
                    "confidence": "high/medium/low"
                }"""
                vlm_result = query_vlm(images=images, prompt=prompt)
                
                if vlm_result and vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("properties_dialog_used", False):
                        vlm_points = 10
                        feedback_parts.append("VLM confirmed manual properties editing UI usage")
                    else:
                        feedback_parts.append("VLM did not observe the properties dialog being used")
        except Exception as e:
            logger.warning(f"VLM verification skipped or failed: {e}")

    score += vlm_points

    # Final Pass Logic: Threshold is 75 points.
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }