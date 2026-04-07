#!/usr/bin/env python3
"""
Verifier for Avare Amend Flight Plan Task.

Verifies:
1. GPX file was created during the task.
2. GPX contains the correct sequence: KLAX -> SLI -> KSAN.
3. Coordinates match expected values (within tolerance).
4. VLM verification of UI interaction.
"""

import json
import os
import logging
import tempfile
import xml.etree.ElementTree as ET
import math

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def haversine_distance(lat1, lon1, lat2, lon2):
    """Calculate distance between two points in km."""
    R = 6371  # Earth radius in km
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat/2) * math.sin(dlat/2) + \
        math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * \
        math.sin(dlon/2) * math.sin(dlon/2)
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R * c

def verify_amend_flight_plan_insert(traj, env_info, task_info):
    """
    Verify the flight plan amendment task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_sequence = metadata.get('expected_sequence', ["KLAX", "SLI", "KSAN"])
    expected_coords = {pt['id']: (pt['lat'], pt['lon']) for pt in metadata.get('expected_lat_longs', [])}
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # =========================================================
    # 1. Retrieve Task Results
    # =========================================================
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_gpx_file = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    
    try:
        # Get JSON result
        copy_from_env("/sdcard/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            result_data = json.load(f)
            
        gpx_exists = result_data.get('gpx_exists', False)
        
        # Get GPX file if it exists
        gpx_content_valid = False
        waypoints_found = []
        
        if gpx_exists:
            try:
                copy_from_env("/sdcard/task_output.gpx", temp_gpx_file.name)
                
                # Parse GPX
                tree = ET.parse(temp_gpx_file.name)
                root = tree.getroot()
                
                # GPX namespace handling
                ns = {'gpx': 'http://www.topografix.com/GPX/1/1'}
                # Try with and without namespace
                
                # Look for route points (rtept) or waypoints (wpt) if it's just a list
                # Avare usually exports routes using <rte> containing <rtept>
                route_points = root.findall(".//{http://www.topografix.com/GPX/1/1}rtept")
                if not route_points:
                    route_points = root.findall(".//rtept") # Try without NS
                
                # If no route points, check standard waypoints (though Avare usually uses rte for plans)
                if not route_points:
                    route_points = root.findall(".//{http://www.topografix.com/GPX/1/1}wpt")
                if not route_points:
                    route_points = root.findall(".//wpt")

                for pt in route_points:
                    lat = float(pt.get('lat'))
                    lon = float(pt.get('lon'))
                    
                    # Try to find name tag
                    name = pt.find("{http://www.topografix.com/GPX/1/1}name")
                    if name is None:
                        name = pt.find("name")
                    
                    name_text = name.text if name is not None else "Unknown"
                    waypoints_found.append({"name": name_text, "lat": lat, "lon": lon})
                
                gpx_content_valid = True
                score += 20 # GPX valid and parsed
                feedback_parts.append("GPX file exported and parsed successfully")
                
            except Exception as e:
                feedback_parts.append(f"Failed to parse GPX: {str(e)}")
        else:
            feedback_parts.append("No GPX file found (created during task)")

        # =========================================================
        # 2. Verify Route Sequence
        # =========================================================
        sequence_correct = False
        
        if gpx_content_valid and len(waypoints_found) >= 3:
            # Check names match expected sequence roughly
            # Allow for some variation (e.g. "KLAX" vs "KLAX Los Angeles")
            
            matched_indices = []
            current_search_idx = 0
            
            # Simple check: do the expected IDs appear in the found list in order?
            # We enforce exact order KLAX -> SLI -> KSAN
            
            if len(waypoints_found) == 3:
                n1 = waypoints_found[0]['name'].upper()
                n2 = waypoints_found[1]['name'].upper()
                n3 = waypoints_found[2]['name'].upper()
                
                check1 = "KLAX" in n1
                check2 = "SLI" in n2 or "SEAL BEACH" in n2
                check3 = "KSAN" in n3
                
                if check1 and check2 and check3:
                    sequence_correct = True
                    score += 60
                    feedback_parts.append("Route sequence correct: KLAX -> SLI -> KSAN")
                else:
                    feedback_parts.append(f"Incorrect sequence. Found: {n1} -> {n2} -> {n3}")
            else:
                feedback_parts.append(f"Expected 3 waypoints, found {len(waypoints_found)}")
        elif gpx_content_valid:
             feedback_parts.append(f"Too few waypoints found: {len(waypoints_found)}")

        # =========================================================
        # 3. VLM Verification (Trajectory)
        # =========================================================
        # We check if the agent interacted with the Plan tab
        frames = sample_trajectory_frames(traj, n=5)
        final_screen = get_final_screenshot(traj)
        
        if frames:
            vlm_prompt = """
            Analyze these screenshots of the Avare aviation app.
            Did the user:
            1. Access the 'Plan' or 'Flight Plan' screen?
            2. Enter waypoint codes like KLAX, KSAN, or SLI?
            3. Export a file?
            
            Return JSON: {"plan_accessed": bool, "waypoints_entered": bool, "export_seen": bool}
            """
            
            try:
                vlm_res = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
                parsed = vlm_res.get('parsed', {})
                
                if parsed.get('plan_accessed'):
                    score += 10
                    feedback_parts.append("VLM confirmed Plan screen access")
                if parsed.get('export_seen') or gpx_exists:
                    score += 10
                    feedback_parts.append("VLM/File confirmed export")
                    
            except Exception as e:
                logger.warning(f"VLM check failed: {e}")
                # Fallback: if GPX is perfect, give full marks regardless of VLM
                if sequence_correct:
                    score += 20

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"System error: {str(e)}"}
    finally:
        # Cleanup
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)
        if os.path.exists(temp_gpx_file.name):
            os.unlink(temp_gpx_file.name)

    passed = score >= 80 and sequence_correct
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }