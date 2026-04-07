#!/usr/bin/env python3
"""
Verifier for reverse_route_direction task.

Verifies:
1. Exported GPX file exists and was created during the task.
2. Route name in GPX is exactly "Fells Return Patrol".
3. Route points are reversed (First point is South Border Road Gate, last is Sheepfold Parking).
4. All 5 via points are present.
5. Trajectory frames show BaseCamp interaction.
"""

import os
import json
import tempfile
import xml.etree.ElementTree as ET

def strip_ns(tag):
    """Strip XML namespaces for easier matching."""
    return tag.split('}')[-1] if '}' in tag else tag

def verify_reverse_route_direction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_route_name = metadata.get('expected_route_name', 'Fells Return Patrol')
    expected_start_lat = metadata.get('expected_start_lat', 42.4340)
    expected_end_lat = metadata.get('expected_end_lat', 42.4380)
    tol = metadata.get('tolerance_deg', 0.001)

    score = 0
    feedback_parts = []

    # 1. Retrieve the task result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check GPX existence and timestamps (Anti-gaming)
    output_exists = result.get('output_exists') == "true"
    file_created = result.get('file_created_during_task') == "true"

    if output_exists:
        score += 15
        feedback_parts.append("GPX File exists")
    else:
        feedback_parts.append("GPX File missing")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    if file_created:
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp predates task (Anti-gaming trigger)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 3. Retrieve and parse exported GPX file
    temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    try:
        copy_from_env("C:\\tmp\\exported_route.gpx", temp_gpx.name)
        tree = ET.parse(temp_gpx.name)
        root = tree.getroot()
    except Exception as e:
        if os.path.exists(temp_gpx.name):
            os.unlink(temp_gpx.name)
        return {"passed": False, "score": score, "feedback": f"Failed to parse GPX: {e}"}
    finally:
        if os.path.exists(temp_gpx.name):
            os.unlink(temp_gpx.name)

    # Locate Route (<rte>)
    rte_element = None
    for child in root:
        if strip_ns(child.tag) == 'rte':
            rte_element = child
            break

    if not rte_element:
        feedback_parts.append("No route found in GPX")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Check Route Name
    route_name = ""
    for elem in rte_element:
        if strip_ns(elem.tag) == 'name':
            route_name = elem.text
            break

    if route_name == expected_route_name:
        score += 20
        feedback_parts.append("Route name correct")
    else:
        feedback_parts.append(f"Route name incorrect (found: {route_name})")

    # Check Route Points (<rtept>)
    rtepts = []
    for elem in rte_element:
        if strip_ns(elem.tag) == 'rtept':
            lat = float(elem.attrib.get('lat', 0))
            rtepts.append(lat)

    points_reversed = False
    if len(rtepts) >= 5:
        score += 15
        feedback_parts.append("All 5 via points present")
        
        # Verify direction
        first_lat = rtepts[0]
        last_lat = rtepts[-1]
        
        if abs(first_lat - expected_start_lat) < tol and abs(last_lat - expected_end_lat) < tol:
            score += 30
            points_reversed = True
            feedback_parts.append("Route points successfully reversed")
        elif abs(first_lat - expected_end_lat) < tol and abs(last_lat - expected_start_lat) < tol:
            feedback_parts.append("Route points NOT reversed (Original order found)")
        else:
            feedback_parts.append("Route points sequence is invalid")
    else:
        feedback_parts.append(f"Expected 5 route points, found {len(rtepts)}")

    # 4. VLM Verification (Trajectory checking)
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = (
                "Review these frames from a user operating Garmin BaseCamp. "
                "1. Did the user right-click or use the menu on a route named 'Fells Morning Patrol'? "
                "2. Did the user interact with 'Invert' or 'Reverse' route functionality? "
                "3. Did the user open route properties to rename it? "
                "4. Is the export dialog visible in any frame? "
                "Answer yes/no for each and conclude if the workflow was generally followed. "
                "Return JSON: {\"workflow_followed\": true/false}"
            )
            vlm_response = query_vlm(images=frames, prompt=prompt)
            if vlm_response.get("success") and vlm_response.get("parsed", {}).get("workflow_followed", False):
                score += 10
                feedback_parts.append("VLM confirmed trajectory actions")
    except Exception as e:
        feedback_parts.append(f"VLM verification skipped/failed: {e}")

    # Pass logic
    passed = score >= 65 and points_reversed

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }