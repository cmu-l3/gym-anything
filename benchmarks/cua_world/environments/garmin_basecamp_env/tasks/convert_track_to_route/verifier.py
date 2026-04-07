#!/usr/bin/env python3
"""
Verifier for convert_track_to_route task in Garmin BaseCamp.

Verifies the output GPX file to ensure:
1. File exists and was generated during the task.
2. Contains a valid <rte> (route) element.
3. Route is accurately named "Fells Survey Route".
4. Route contains an appropriate number of points (>=5).
5. Route points fall within the expected geographic bounding box.
"""

import json
import os
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_convert_track_to_route(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_export_path', 'C:\\Users\\Docker\\Documents\\fells_survey_export.gpx')
    expected_name = metadata.get('expected_route_name', 'Fells Survey Route')
    min_points = metadata.get('min_route_points', 5)
    bounds = metadata.get('geo_bounds', {
        "lat_min": 42.41, "lat_max": 42.49,
        "lon_min": -71.14, "lon_max": -71.06
    })

    score = 0
    feedback = []

    # 1. Read task_result.json metadata
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\GarminTools\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to read task result metadata: {e}")
        result_meta = {"output_exists": False}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Validate file presence and timestamp
    if result_meta.get("output_exists"):
        score += 15
        feedback.append("Exported file found.")
    else:
        feedback.append("FAIL: Exported file not found.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    if result_meta.get("file_created_during_task"):
        score += 15
        feedback.append("File created during the task.")
    else:
        feedback.append("FAIL: File timestamp indicates it was created before the task started (Gaming detected).")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Parse the GPX file
    temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    try:
        copy_from_env(expected_path, temp_gpx.name)
        
        try:
            tree = ET.parse(temp_gpx.name)
            root = tree.getroot()
        except ET.ParseError as e:
            feedback.append(f"FAIL: GPX file is not valid XML ({e}).")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

        # Helper to bypass namespace issues
        def get_local_name(tag):
            return tag.split('}')[-1]

        # Find all routes
        routes = []
        for elem in root.iter():
            if get_local_name(elem.tag) == 'rte':
                routes.append(elem)

        if not routes:
            feedback.append("FAIL: GPX does not contain any routes (<rte> elements). Did you only export the track?")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback)}
        
        score += 20
        feedback.append(f"Found {len(routes)} route(s).")

        # Evaluate routes
        target_route = None
        for rte in routes:
            rte_name = ""
            for child in rte:
                if get_local_name(child.tag) == 'name' and child.text:
                    rte_name = child.text.strip()
                    break
            
            if rte_name == expected_name:
                target_route = rte
                break
        
        if target_route is not None:
            score += 20
            feedback.append(f"Route named '{expected_name}' found.")
        else:
            feedback.append(f"FAIL: No route found with the exact name '{expected_name}'.")
            # For the sake of partial points on geometry, fall back to the first route found
            target_route = routes[0]

        # Check route points
        rtepts = []
        for child in target_route:
            if get_local_name(child.tag) == 'rtept':
                rtepts.append(child)

        if len(rtepts) >= min_points:
            score += 15
            feedback.append(f"Route contains a valid number of points ({len(rtepts)}).")
        else:
            feedback.append(f"FAIL: Route has too few points ({len(rtepts)} < {min_points}).")

        # Check point geometry bounds
        valid_geo_pts = 0
        for pt in rtepts:
            try:
                lat = float(pt.attrib.get('lat', 0))
                lon = float(pt.attrib.get('lon', 0))
                if (bounds["lat_min"] <= lat <= bounds["lat_max"] and
                    bounds["lon_min"] <= lon <= bounds["lon_max"]):
                    valid_geo_pts += 1
            except (ValueError, TypeError):
                pass
        
        if len(rtepts) > 0 and (valid_geo_pts / len(rtepts)) > 0.8:
            score += 15
            feedback.append("Route points align with valid Fells geographic coordinates.")
        elif len(rtepts) > 0:
            feedback.append("FAIL: Route points fall outside the expected bounds. (Did you use the correct track?)")

    except Exception as e:
        logger.error(f"Error during file evaluation: {e}")
        feedback.append(f"Error accessing or parsing export file: {e}")
    finally:
        if os.path.exists(temp_gpx.name):
            os.unlink(temp_gpx.name)

    # Determine passing status
    # Must have >= 60 points, route found, correctly named, and file created during task
    passed = (score >= 60 and 
              result_meta.get("file_created_during_task", False) and 
              target_route is not None and 
              "FAIL: No route found with the exact name" not in " ".join(feedback))

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }