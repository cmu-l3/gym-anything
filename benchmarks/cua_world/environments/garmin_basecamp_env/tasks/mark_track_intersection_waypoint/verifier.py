#!/usr/bin/env python3
"""
Verifier for mark_track_intersection_waypoint task.

Verification metrics:
1. Output GPX exists and is valid XML (10 pts)
2. File created during the task run (anti-gaming) (10 pts)
3. Name matches "Incursion" exactly (10 pts)
4. Data Isolation (Only 1 waypoint, NO tracks exported) (10 pts)
5. Spatial accuracy calculation (Distance to ground truth) (Max 50 pts)
6. VLM Trajectory (Interacted with tools) (10 pts)
"""

import json
import os
import tempfile
import math
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def haversine(lat1, lon1, lat2, lon2):
    """Calculate the great circle distance in meters between two points."""
    R = 6371000  # radius of Earth in meters
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)

    a = math.sin(delta_phi / 2.0) ** 2 + \
        math.cos(phi1) * math.cos(phi2) * \
        math.sin(delta_lambda / 2.0) ** 2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c


def verify_mark_intersection(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_waypoint_name', 'Incursion')
    fair_dist = metadata.get('tolerance_fair_meters', 100.0)
    exc_dist = metadata.get('tolerance_excellent_meters', 30.0)

    score = 0
    feedback_parts = []
    
    # === 1. Copy necessary files ===
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')

    try:
        # Load exported task result state
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        # Load Ground Truth
        copy_from_env("C:\\tmp\\ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
            gt_lat = float(gt_data['intersection_lat'])
            gt_lon = float(gt_data['intersection_lon'])

        # Load GPX File (if it exists)
        gpx_valid = False
        wpt_count, trk_count = 0, 0
        agent_lat, agent_lon = None, None
        agent_name = ""

        if result.get("output_exists", False):
            try:
                copy_from_env("C:\\workspace\\output\\incursion_point.gpx", temp_gpx.name)
                tree = ET.parse(temp_gpx.name)
                root = tree.getroot()
                
                # Use wildcard to ignore namespaces e.g. .//{http://...}wpt
                wpts = root.findall('.//{*}wpt')
                trks = root.findall('.//{*}trk')
                
                wpt_count = len(wpts)
                trk_count = len(trks)
                gpx_valid = True

                if wpt_count > 0:
                    agent_lat = float(wpts[0].attrib.get('lat', 0))
                    agent_lon = float(wpts[0].attrib.get('lon', 0))
                    name_node = wpts[0].find('.//{*}name')
                    if name_node is not None and name_node.text:
                        agent_name = name_node.text.strip()
                        
            except ET.ParseError:
                feedback_parts.append("File exists but is invalid XML")
            except Exception as e:
                feedback_parts.append(f"GPX parse error: {str(e)}")
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Failed to extract required files from environment."}
    finally:
        for tmp in [temp_result.name, temp_gpx.name, temp_gt.name]:
            if os.path.exists(tmp):
                os.unlink(tmp)

    # === 2. Verification Scoring ===

    # Structural / Existence (10 pts + 10 pts)
    if gpx_valid:
        score += 10
        feedback_parts.append("GPX file successfully created and parsed")
        
        if result.get("file_created_during_task", False):
            score += 10
            feedback_parts.append("File confirmed created during task run")
        else:
            feedback_parts.append("Warning: File timestamp predates task start (possible artifact)")
    else:
        feedback_parts.append("Failed to find or parse valid GPX file")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Name check (10 pts)
    if agent_name.lower() == expected_name.lower():
        score += 10
        feedback_parts.append(f"Waypoint correctly named '{expected_name}'")
    elif agent_name:
        feedback_parts.append(f"Waypoint named '{agent_name}' instead of '{expected_name}'")
    else:
        feedback_parts.append("Waypoint missing a name tag")

    # Data Isolation (10 pts) - Agent shouldn't export tracks, ONLY the waypoint
    if wpt_count == 1 and trk_count == 0:
        score += 10
        feedback_parts.append("Export isolated to single waypoint (no tracks exported)")
    else:
        feedback_parts.append(f"Data isolation failed (Found {wpt_count} waypoints, {trk_count} tracks)")

    # Spatial Accuracy (Max 50 pts)
    if agent_lat is not None and agent_lon is not None:
        dist = haversine(agent_lat, agent_lon, gt_lat, gt_lon)
        
        if dist <= exc_dist:
            score += 50
            feedback_parts.append(f"Excellent placement accuracy (Distance: {dist:.1f}m <= {exc_dist}m)")
        elif dist <= fair_dist:
            score += 30
            feedback_parts.append(f"Fair placement accuracy (Distance: {dist:.1f}m <= {fair_dist}m)")
        else:
            feedback_parts.append(f"Placement inaccurate (Distance: {dist:.1f}m away from actual intersection)")
    else:
        feedback_parts.append("No geographic coordinates found in exported GPX")

    # === 3. VLM Trajectory Verification ===
    # Check if they actually clicked the map / used tools instead of blind exporting
    vlm_pts = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        
        prompt = """Analyze these progression screenshots from a Garmin BaseCamp session.
        The user's objective was to visually locate the crossing of two track lines and create a waypoint precisely there.
        
        Did the user sequence demonstrate:
        1. Panning/zooming the map view to the geographic intersection?
        2. Selecting or using the Waypoint tool (flag icon)?
        3. Opening a Waypoint Properties dialog?
        
        Respond with JSON:
        {"map_interacted": true/false, "waypoint_tool_used": true/false, "properties_opened": true/false}
        """
        vlm_result = query_vlm(images=frames, prompt=prompt)
        
        if vlm_result.get('success'):
            parsed = vlm_result.get('parsed', {})
            if parsed.get('map_interacted') or parsed.get('waypoint_tool_used') or parsed.get('properties_opened'):
                vlm_pts = 10
                feedback_parts.append("VLM confirmed visual UI interaction")
    except Exception as e:
        logger.warning(f"VLM check skipped or failed: {e}")

    score += vlm_pts

    # === Final Determination ===
    # Requires base GPX structure + at least Fair placement distance + Some combination getting to >= 70
    passed = (score >= 70) and (wpt_count >= 1) and (dist <= fair_dist if 'dist' in locals() else False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }