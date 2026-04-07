#!/usr/bin/env python3
"""
Verifier for the Convert KML GIS Boundary to GPX Patrol Map task.

Checks:
1. Exported file exists and was created during the task.
2. The track is correctly named "Fells Reservation Boundary".
3. The track display color is set to "Magenta".
4. Data authenticity: The track retains the >100 points imported from the KML.
5. Waypoint "South Entrance" is present in the file.
6. Waypoint coordinates are correct within tolerance.
"""

import json
import tempfile
import os
import xml.etree.ElementTree as ET
import math

def verify_kml_to_gpx_conversion(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', 'C:\\workspace\\output\\patrol_boundary.gpx')
    expected_track = metadata.get('expected_track_name', 'Fells Reservation Boundary')
    expected_color = metadata.get('expected_color', 'Magenta')
    expected_wpt = metadata.get('expected_waypoint_name', 'South Entrance')
    target_lat = metadata.get('target_lat', 42.438)
    target_lon = metadata.get('target_lon', -71.105)
    tolerance = metadata.get('coordinate_tolerance', 0.005)
    min_points = metadata.get('min_track_points', 100)

    score = 0
    feedback = []

    # 1. Copy and read task_result.json
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\output\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Check basic file existence
    if not result.get('output_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Exported GPX file not found at the expected path."
        }
    
    if not result.get('file_created_during_task', False):
        feedback.append("Warning: File timestamp indicates it might not have been created during this session.")
        
    score += 10
    feedback.append("GPX file exported successfully (+10).")

    # 2. Copy and parse the GPX file
    temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    try:
        copy_from_env(expected_path, temp_gpx.name)
        tree = ET.parse(temp_gpx.name)
        root = tree.getroot()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"File exported but invalid XML: {e}"}
    finally:
        if os.path.exists(temp_gpx.name):
            os.unlink(temp_gpx.name)

    # Namespaces commonly used by Garmin BaseCamp GPX exports
    ns = {
        'gpx': 'http://www.topografix.com/GPX/1/1',
        'gpxx': 'http://www.garmin.com/xmlschemas/GpxExtensions/v3'
    }

    # Helper function to ignore namespaces if strict parsing fails
    def find_all_tags(xml_root, tag_name):
        return [el for el in xml_root.iter() if el.tag.endswith('}' + tag_name) or el.tag == tag_name]

    # --- Criteria 2: Track Renaming (+15) ---
    track_names = [el.text for el in find_all_tags(root, 'name') if el.text]
    if expected_track in track_names:
        score += 15
        feedback.append("Track correctly renamed (+15).")
    else:
        feedback.append(f"Expected track name '{expected_track}' not found.")

    # --- Criteria 3: Color Configuration (+20) ---
    color_found = False
    for el in find_all_tags(root, 'DisplayColor'):
        if el.text and el.text.lower() == expected_color.lower():
            color_found = True
            break
            
    if color_found:
        score += 20
        feedback.append(f"Track color correctly set to {expected_color} (+20).")
    else:
        feedback.append("DisplayColor not set to Magenta.")

    # --- Criteria 4: Data Authenticity (+25) ---
    track_points = find_all_tags(root, 'trkpt')
    if len(track_points) >= min_points:
        score += 25
        feedback.append(f"Data authenticity verified ({len(track_points)} points retained) (+25).")
    else:
        feedback.append(f"Data lost: Expected >{min_points} points, found {len(track_points)}. Did you draw a fake track?")

    # --- Criteria 5 & 6: Waypoint Creation and Accuracy (+15, +15) ---
    wpt_found = False
    coords_accurate = False
    
    # Search all waypoints
    for wpt in root.findall('.//gpx:wpt', ns) or find_all_tags(root, 'wpt'):
        # Get name inside waypoint
        name_elem = wpt.find('gpx:name', ns)
        if name_elem is None:
            # Try namespace-agnostic search for name within this wpt
            for child in wpt:
                if child.tag.endswith('name'):
                    name_elem = child
                    break
                    
        if name_elem is not None and name_elem.text == expected_wpt:
            wpt_found = True
            lat_str = wpt.get('lat')
            lon_str = wpt.get('lon')
            if lat_str and lon_str:
                lat = float(lat_str)
                lon = float(lon_str)
                if abs(lat - target_lat) <= tolerance and abs(lon - target_lon) <= tolerance:
                    coords_accurate = True
            break

    if wpt_found:
        score += 15
        feedback.append("Waypoint 'South Entrance' found (+15).")
        if coords_accurate:
            score += 15
            feedback.append("Waypoint coordinates are within the target tolerance (+15).")
        else:
            feedback.append("Waypoint coordinates are incorrect or outside the 0.005 degree tolerance.")
    else:
        feedback.append("Waypoint 'South Entrance' not found in export.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }