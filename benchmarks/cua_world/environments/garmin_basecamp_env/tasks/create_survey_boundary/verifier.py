#!/usr/bin/env python3
"""
Verifier for create_survey_boundary task.

This evaluates the exported GPX file to ensure:
1. Four waypoints (NW-CORNER, NE-CORNER, SE-CORNER, SW-CORNER) were created.
2. The waypoints form a bounding box that fully encompasses the fells_loop track.
3. The waypoints are within the expected +/- 0.003 degree padded tolerances.
4. A 'Survey Boundary' route connects the waypoints.
5. The route forms a closed loop.
"""

import os
import json
import tempfile
import xml.etree.ElementTree as ET
import logging
from math import isclose

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM utilities if available
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    HAS_VLM = True
except ImportError:
    HAS_VLM = False


def strip_ns(tag):
    """Strip XML namespace for easier parsing."""
    return tag.split('}', 1)[1] if '}' in tag else tag


def verify_create_survey_boundary(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not provided"}

    feedback_parts = []
    score = 0

    # 1. Fetch metadata & results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load export result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Base requirements
    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)

    if not output_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Exported file C:\\workspace\\output\\survey_boundary.gpx was not found. Agent failed to export."
        }
    
    if not file_created_during_task:
        feedback_parts.append("WARNING: File timestamp predates task start (Anti-gaming flag)")
    
    score += 10
    feedback_parts.append("GPX file exists")

    # 2. Parse the GPX file
    temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    try:
        copy_from_env("C:\\workspace\\output\\survey_boundary.gpx", temp_gpx.name)
        tree = ET.parse(temp_gpx.name)
        root = tree.getroot()
    except ET.ParseError:
        return {"passed": False, "score": score, "feedback": "GPX file exists but contains invalid XML"}
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Error accessing GPX file: {e}"}
    finally:
        if os.path.exists(temp_gpx.name):
            os.unlink(temp_gpx.name)

    # 3. Extract Waypoints and Routes
    waypoints = {}
    routes = []

    for child in root:
        tag = strip_ns(child.tag)
        if tag == 'wpt':
            try:
                lat = float(child.attrib.get('lat', 0))
                lon = float(child.attrib.get('lon', 0))
                name = ""
                for sub in child:
                    if strip_ns(sub.tag) == 'name':
                        name = sub.text.strip() if sub.text else ""
                waypoints[name.upper()] = {"lat": lat, "lon": lon, "name": name}
            except ValueError:
                continue
        elif tag == 'rte':
            r_name = ""
            rtepts = []
            for sub in child:
                sub_tag = strip_ns(sub.tag)
                if sub_tag == 'name':
                    r_name = sub.text.strip() if sub.text else ""
                elif sub_tag == 'rtept':
                    pt_name = ""
                    for r_sub in sub:
                        if strip_ns(r_sub.tag) == 'name':
                            pt_name = r_sub.text.strip() if r_sub.text else ""
                    rtepts.append(pt_name.upper())
            routes.append({"name": r_name, "points": rtepts})

    # 4. Check Waypoints
    expected_names = ["NW-CORNER", "NE-CORNER", "SE-CORNER", "SW-CORNER"]
    found_expected = [name for name in expected_names if name in waypoints]
    
    if len(waypoints) == 4 and len(found_expected) == 4:
        score += 15
        feedback_parts.append("Exactly 4 waypoints present")
    elif len(found_expected) == 4:
        score += 10
        feedback_parts.append("4 expected waypoints found (but file contains extra waypoints)")
    else:
        feedback_parts.append(f"Missing expected waypoints. Found: {list(waypoints.keys())}")

    if len(found_expected) == 4:
        score += 10
        feedback_parts.append("Correct waypoint names used")

    # 5. Check Coordinates with expected bounds
    # Reference Tolerances (approx +- 0.003 degrees from ideal targets)
    bounds_checks = {
        "NW-CORNER": {"lat_min": 42.447, "lat_max": 42.453, "lon_min": -71.115, "lon_max": -71.109},
        "NE-CORNER": {"lat_min": 42.447, "lat_max": 42.453, "lon_min": -71.096, "lon_max": -71.090},
        "SE-CORNER": {"lat_min": 42.433, "lat_max": 42.439, "lon_min": -71.096, "lon_max": -71.090},
        "SW-CORNER": {"lat_min": 42.433, "lat_max": 42.439, "lon_min": -71.115, "lon_max": -71.109}
    }

    geom_valid = True
    encloses_track = True

    for wp_name, limits in bounds_checks.items():
        if wp_name in waypoints:
            lat = waypoints[wp_name]["lat"]
            lon = waypoints[wp_name]["lon"]
            if limits["lat_min"] <= lat <= limits["lat_max"] and limits["lon_min"] <= lon <= limits["lon_max"]:
                score += 5
            else:
                feedback_parts.append(f"{wp_name} coordinates out of bounds (Lat: {lat}, Lon: {lon})")
                geom_valid = False
            
            # Rough check if it encloses the core track coordinates (42.438 -> 42.448 / -71.110 -> -71.095)
            if wp_name.startswith("N") and lat < 42.448: encloses_track = False
            if wp_name.startswith("S") and lat > 42.438: encloses_track = False
            if wp_name.endswith("W-CORNER") and lon > -71.110: encloses_track = False
            if wp_name.endswith("E-CORNER") and lon < -71.095: encloses_track = False

    if encloses_track and len(found_expected) == 4:
        score += 10
        feedback_parts.append("Bounding box successfully encloses track extent")

    # Axis alignment check for rectangle (latitudes of N should match closely, etc.)
    if len(found_expected) == 4:
        n_lat_diff = abs(waypoints["NW-CORNER"]["lat"] - waypoints["NE-CORNER"]["lat"])
        s_lat_diff = abs(waypoints["SW-CORNER"]["lat"] - waypoints["SE-CORNER"]["lat"])
        if n_lat_diff < 0.002 and s_lat_diff < 0.002:
            score += 5
            feedback_parts.append("Rectangle geometry is properly axis-aligned")

    # 6. Check Route
    target_route = next((r for r in routes if r['name'].upper() == "SURVEY BOUNDARY"), None)
    
    if target_route:
        score += 10
        feedback_parts.append("Route 'Survey Boundary' exists")
        
        pts = target_route["points"]
        if len(pts) >= 4:
            score += 10
            feedback_parts.append("Route contains at least 4 points")
            
            # Check closed loop
            if len(pts) >= 5 and pts[0] == pts[-1] and len(set(pts)) >= 4:
                score += 5
                feedback_parts.append("Route is a closed loop")
            else:
                feedback_parts.append("Route does not form a closed loop ending at the start point")
    else:
        feedback_parts.append("Route 'Survey Boundary' not found")

    # 7. VLM Visual Check (Bonus / secondary confirmation)
    if HAS_VLM and traj:
        try:
            frames = sample_trajectory_frames(traj, n=3)
            final_img = get_final_screenshot(traj)
            if frames and final_img:
                images = frames + [final_img]
                prompt = (
                    "You are verifying a Garmin BaseCamp task. Look at these frames. "
                    "Did the user successfully draw a rectangular boundary route around a trail on the map? "
                    "Respond with a JSON object: {\"visual_confirmed\": true/false}"
                )
                vlm_resp = query_vlm(images=images, prompt=prompt)
                if vlm_resp.get("parsed", {}).get("visual_confirmed", False):
                    score += 5
                    feedback_parts.append("VLM visual confirmation passed")
        except Exception as e:
            logger.warning(f"VLM verification skipped or failed: {e}")

    # Max possible score = 100
    passed = score >= 60 and output_exists and target_route is not None

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }