#!/usr/bin/env python3
"""
Verifier for modify_route_sequence task.
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_modify_route_sequence(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Read task_result.json
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    output_exists = result.get("output_exists", False)
    file_created = result.get("file_created_during_task", False)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "modified_survey.gpx was not found in C:\\workspace\\output\\"}
        
    if file_created:
        score += 10
        feedback_parts.append("File exported during task")
    else:
        feedback_parts.append("File was not created during the task timeframe")
        
    # 2. Parse GPX file
    temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    try:
        copy_from_env("C:\\workspace\\output\\modified_survey.gpx", temp_gpx.name)
        
        tree = ET.parse(temp_gpx.name)
        root = tree.getroot()
        
        # GPX uses namespaces, e.g., xmlns="http://www.topografix.com/GPX/1/1"
        ns = {'gpx': 'http://www.topografix.com/GPX/1/1'}
        
        routes = root.findall('.//gpx:rte', ns)
        if not routes:
            # Try without namespace or with 1.0 namespace
            routes = root.findall('.//rte')
            if not routes:
                ns = {'gpx': 'http://www.topografix.com/GPX/1/0'}
                routes = root.findall('.//gpx:rte', ns)
                
        if not routes:
            return {"passed": False, "score": score, "feedback": "No route (<rte>) found in GPX file."}
            
        route = routes[0] # Verify the first route found
        
        # Check name
        name_elem = route.find('gpx:name', ns)
        if name_elem is None:
            name_elem = route.find('name')
            
        route_name = name_elem.text.strip() if name_elem is not None and name_elem.text else ""
        
        if route_name == "Fells Modified Survey":
            score += 20
            feedback_parts.append("Route renamed correctly")
        elif "Modified" in route_name:
            score += 10
            feedback_parts.append("Route partially renamed")
        else:
            feedback_parts.append(f"Incorrect route name: '{route_name}'")
            
        # Check points
        rtepts = route.findall('gpx:rtept', ns)
        if not rtepts:
            rtepts = route.findall('rtept')
            
        point_names = []
        has_valid_coords = True
        for pt in rtepts:
            # Check coords to ensure it wasn't a manual fake file
            lat = float(pt.get('lat', 0.0))
            lon = float(pt.get('lon', 0.0))
            if lat == 0.0 and lon == 0.0:
                has_valid_coords = False
                
            pt_name_elem = pt.find('gpx:name', ns)
            if pt_name_elem is None:
                pt_name_elem = pt.find('name')
            pt_name = pt_name_elem.text.strip() if pt_name_elem is not None and pt_name_elem.text else ""
            point_names.append(pt_name)
            
        if has_valid_coords and len(point_names) > 0:
            score += 10
            feedback_parts.append("Valid coordinates preserved")
            
        # Check sequence
        expected_sequence = [
            "Trailhead", 
            "Intersection 1", 
            "Intersection 2", 
            "Invasive Knotweed Patch", 
            "Intersection 3", 
            "Ranger Station"
        ]
        
        if point_names == expected_sequence:
            score += 60  # 30 for midpoint, 30 for endpoint
            feedback_parts.append("Route sequence matches expected exactly")
        else:
            # Partial scoring
            try:
                i2_idx = point_names.index("Intersection 2")
                knotweed_idx = point_names.index("Invasive Knotweed Patch")
                i3_idx = point_names.index("Intersection 3")
                
                if i2_idx < knotweed_idx < i3_idx and knotweed_idx == i2_idx + 1:
                    score += 30
                    feedback_parts.append("Knotweed correctly inserted")
            except ValueError:
                pass
                
            try:
                ranger_idx = point_names.index("Ranger Station")
                if ranger_idx == len(point_names) - 1:
                    score += 30
                    feedback_parts.append("Ranger Station correctly appended")
            except ValueError:
                pass
                
            feedback_parts.append(f"Sequence found: {point_names}")

    except Exception as e:
        feedback_parts.append(f"Failed to parse GPX: {e}")
    finally:
        if os.path.exists(temp_gpx.name):
            os.unlink(temp_gpx.name)
            
    # VLM Verification to prevent gaming (agent must use BaseCamp GUI)
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """Look at these screenshots from a desktop session. 
            Did the user actively interact with the Garmin BaseCamp application to edit a route and export a GPX file? 
            Look for the Route Properties dialog, drag and drop of waypoints, or the Export dialog. 
            Reply in JSON: {"used_basecamp": true/false}"""
            
            vlm_result = query_vlm(prompt=prompt, images=frames)
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("used_basecamp"):
                    feedback_parts.append("VLM verified BaseCamp usage")
                else:
                    score = min(score, 50)  # Heavy penalty for not using BaseCamp GUI
                    feedback_parts.append("VLM could not verify BaseCamp usage (possible gaming)")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }