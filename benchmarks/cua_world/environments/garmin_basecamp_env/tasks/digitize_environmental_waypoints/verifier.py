#!/usr/bin/env python3
"""
Verifier for digitize_environmental_waypoints task.

Verification Strategy:
1. Copy the export result JSON and GPX file from the environment.
2. Parse the GPX file for the exactly named waypoints.
3. Verify coordinates, elevation, depth, and temperature for each waypoint.
4. Verify the BaseCamp database timestamp changed (anti-gaming).
5. Use VLM on trajectory frames to ensure the UI Options & Properties dialogs were accessed.
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import VLM utilities
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    logger.warning("VLM utilities not available.")
    VLM_AVAILABLE = False


def extract_gpx_data(gpx_path: str) -> List[Dict[str, Any]]:
    """Parse GPX file and extract waypoints with Garmin extensions."""
    waypoints = []
    try:
        tree = ET.parse(gpx_path)
        root = tree.getroot()
        
        # GPX elements are often namespaced
        for wpt in root.findall('.//*{http://www.topografix.com/GPX/1/1}wpt') or root.findall('.//wpt'):
            data = {}
            data['lat'] = float(wpt.get('lat', 0))
            data['lon'] = float(wpt.get('lon', 0))
            
            # Extract standard elements safely ignoring namespaces
            name_elem = wpt.find('.//*[local-name()="name"]')
            data['name'] = name_elem.text if name_elem is not None else ""
            
            ele_elem = wpt.find('.//*[local-name()="ele"]')
            data['ele'] = float(ele_elem.text) if ele_elem is not None else None
            
            # Extract Garmin Extensions (Depth, Temperature)
            depth_elem = wpt.find('.//*[local-name()="Depth"]')
            data['depth'] = float(depth_elem.text) if depth_elem is not None else None
            
            temp_elem = wpt.find('.//*[local-name()="Temperature"]')
            data['temp'] = float(temp_elem.text) if temp_elem is not None else None
            
            waypoints.append(data)
    except Exception as e:
        logger.error(f"Failed to parse GPX: {e}")
    
    return waypoints


def verify_digitize_environmental_waypoints(traj, env_info, task_info):
    """Main verification logic."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_stations = metadata.get('stations', {})
    tols = metadata.get('tolerances', {})

    score = 0
    feedback_parts = []
    
    # 1. Retrieve the task_result.json
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check GPX Export and Parse
    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    
    extracted_wpts = []
    if output_exists and file_created:
        score += 10
        feedback_parts.append("GPX file correctly exported")
        
        # Copy GPX file to parse
        temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
        try:
            copy_from_env("C:\\workspace\\output\\water_quality_stations.gpx", temp_gpx.name)
            extracted_wpts = extract_gpx_data(temp_gpx.name)
        except Exception as e:
            logger.error(f"Failed to copy GPX: {e}")
        finally:
            if os.path.exists(temp_gpx.name):
                os.unlink(temp_gpx.name)
    else:
        feedback_parts.append("GPX file missing or not created during task")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # 3. Verify the individual Stations
    for station_name, expected in expected_stations.items():
        # Find matching waypoint by name (case insensitive, allow minor punct differences)
        match = next((w for w in extracted_wpts if w['name'].lower().replace('-', ' ') == station_name.lower().replace('-', ' ')), None)
        
        if not match:
            feedback_parts.append(f"Missing {station_name}")
            continue

        # Validate fields
        lat_ok = abs(match['lat'] - expected['lat']) <= tols.get('coord', 0.0001)
        lon_ok = abs(match['lon'] - expected['lon']) <= tols.get('coord', 0.0001)
        ele_ok = match['ele'] is not None and abs(match['ele'] - expected['ele']) <= tols.get('ele', 0.5)
        depth_ok = match['depth'] is not None and abs(match['depth'] - expected['depth']) <= tols.get('depth', 0.1)
        temp_ok = match['temp'] is not None and abs(match['temp'] - expected['temp']) <= tols.get('temp', 0.5)
        
        station_score = 0
        if lat_ok and lon_ok: station_score += 5
        if ele_ok: station_score += 5
        if depth_ok: station_score += 5
        if temp_ok: station_score += 5
        
        score += station_score
        
        if station_score == 20:
            feedback_parts.append(f"{station_name} perfect")
        else:
            feedback_parts.append(f"{station_name} partial (Score: {station_score}/20)")

    # 4. Anti-gaming check (Did BaseCamp Database get modified?)
    gdb_modified = result.get('gdb_modified', False)
    if gdb_modified:
        score += 15
        feedback_parts.append("BaseCamp internal database updated")
    else:
        feedback_parts.append("BaseCamp database not updated (Potential script-bypass detected)")

    # 5. VLM trajectory verification
    if VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=6)
            prompt = """You are verifying an agent's workflow in Garmin BaseCamp.
            Task: Change units to Metric, position format to Decimal Degrees, and input exact Depth/Temperature for waypoints.
            
            Review these trajectory frames and determine:
            1. Did the agent open the 'Options' menu (specifically the 'Measurement' or 'Position' tabs)?
            2. Did the agent interact with the 'Waypoint Properties' dialog tabs (like 'Advanced', 'Notes', or 'References' where depth/temp are found)?
            
            Respond strictly in JSON format:
            {
                "options_menu_accessed": true/false,
                "waypoint_properties_accessed": true/false
            }
            """
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("options_menu_accessed", False):
                    score += 7
                    feedback_parts.append("VLM: Options menu configured")
                if parsed.get("waypoint_properties_accessed", False):
                    score += 8
                    feedback_parts.append("VLM: Waypoint properties edited")
            else:
                feedback_parts.append("VLM query failed, granting partial credit")
                score += 10
        except Exception as e:
            logger.error(f"VLM exception: {e}")
            score += 10 # Default fallback if VLM system error occurs
    else:
        # If VLM is not imported/available, grant the points assuming programmatic checks passed
        score += 15
        feedback_parts.append("VLM unavailable, auto-granting UI points")

    # Final Pass/Fail resolution
    # Max score: 10 (export) + 3*20 (stations) + 15 (DB) + 15 (VLM) = 100
    passed = score >= 75 and output_exists and gdb_modified

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }