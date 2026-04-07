#!/usr/bin/env python3
"""
Verifier for isolate_waypoints_by_symbol task in Garmin BaseCamp.

Verifies that:
1. The campsites.gpx file was created during the task.
2. The file is a valid GPX format document.
3. No tracks or routes were accidentally exported (anti-gaming).
4. Exactly 4 waypoints are present in the export.
5. All exported waypoints possess the 'Campground' symbol.
6. The waypoint names perfectly match the ground truth (authenticity).
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET

def verify_isolate_waypoints_by_symbol(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verifier Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_names = set(metadata.get('expected_names', ["North Camp", "South Camp", "River Camp", "Ridge Camp"]))
    
    score = 0
    feedback_parts = []

    # 1. Read the task execution result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env(r"C:\tmp\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task_result.json: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Basic output checks
    output_exists = result.get('output_exists', False)
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "C:\\workspace\\output\\campsites.gpx was not exported/created."}
    score += 10
    feedback_parts.append("Export file found.")

    output_mtime = result.get('output_mtime', 0)
    task_start_time = result.get('task_start_time', 0)
    if output_mtime < task_start_time:
        return {"passed": False, "score": 0, "feedback": "File exists but appears to have been created before the task started."}

    # 3. GPX Parsing and Inspection
    temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    try:
        copy_from_env(r"C:\workspace\output\campsites.gpx", temp_gpx.name)
        
        try:
            tree = ET.parse(temp_gpx.name)
            root = tree.getroot()
            score += 10
            feedback_parts.append("File is valid XML.")
        except ET.ParseError:
            return {"passed": False, "score": score, "feedback": "Exported file is not valid XML."}

        # Safely extract elements without tying logic strictly to specific namespace versions
        waypoints = []
        tracks_or_routes = 0

        for elem in root.iter():
            tag = elem.tag.split('}')[-1]  # Strip any namespace prefix
            if tag == 'wpt':
                name = ""
                sym = ""
                for child in elem:
                    ctag = child.tag.split('}')[-1]
                    if ctag == 'name':
                        name = child.text
                    elif ctag == 'sym':
                        sym = child.text
                waypoints.append({'name': name, 'sym': sym})
            elif tag in ['trk', 'rte']:
                tracks_or_routes += 1

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Error inspecting GPX: {e}"}
    finally:
        if os.path.exists(temp_gpx.name):
            os.unlink(temp_gpx.name)

    # 4. Detailed Criterion Checks
    
    # Track Absence (Anti-gaming: prevents "Export All")
    if tracks_or_routes == 0:
        score += 20
        feedback_parts.append("No tracks or routes exported (Good isolation).")
    else:
        feedback_parts.append(f"Failed Isolation: Found {tracks_or_routes} track(s)/route(s).")

    # Waypoint Count
    if len(waypoints) == 4:
        score += 20
        feedback_parts.append("Exactly 4 waypoints exported.")
    else:
        feedback_parts.append(f"Waypoint Count Mismatch: Found {len(waypoints)}, expected 4.")

    # Symbol Tag Check
    if len(waypoints) > 0:
        all_campgrounds = all(w['sym'] == 'Campground' for w in waypoints)
        if all_campgrounds:
            score += 20
            feedback_parts.append("All exported waypoints feature the 'Campground' symbol.")
        else:
            feedback_parts.append("Not all waypoints use the 'Campground' symbol.")
    else:
        feedback_parts.append("No waypoints to check symbols for.")

    # Authenticity Check
    actual_names = {w['name'] for w in waypoints if w['name']}
    if actual_names == expected_names:
        score += 20
        feedback_parts.append("Waypoint names precisely match ground-truth dataset.")
    elif len(actual_names) > 0:
        feedback_parts.append(f"Data Mismatch: Exported {actual_names}, Expected {expected_names}.")
    
    # 5. Determine Final Status
    passed = score >= 70 and (len(waypoints) == 4) and (tracks_or_routes == 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }