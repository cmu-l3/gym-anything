#!/usr/bin/env python3
"""
Verifier for analyze_off_trail_detour task.

Verifies:
1. Export file exists and was created during the task run (Anti-gaming).
2. Export file contains exactly 1 waypoint (Agent isolated the selection).
3. The waypoint is named 'Illegal_Camp'.
4. Haversine distance from the exported waypoint to the programmatic ground truth apex.
"""

import json
import tempfile
import os
import math
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def haversine(lat1, lon1, lat2, lon2):
    """Calculate distance between two points in meters."""
    R = 6371000  # Radius of Earth in meters
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    
    a = math.sin(dphi/2)**2 + math.cos(phi1)*math.cos(phi2)*math.sin(dlambda/2)**2
    return 2 * R * math.atan2(math.sqrt(a), math.sqrt(1 - a))

def verify_analyze_off_trail_detour(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_waypoint_name', 'Illegal_Camp')
    thresholds = metadata.get('distance_thresholds_meters', {'high_precision': 15, 'medium_precision': 50, 'low_precision': 150})

    feedback_parts = []
    score = 0
    
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    
    try:
        # Fetch status JSON
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
            
        # Fetch ground truth
        copy_from_env("C:\\tmp\\ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt = json.load(f)
            
        gt_lat = gt.get('apex_lat')
        gt_lon = gt.get('apex_lon')
        
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task data: {e}"}
        
    # 1. Check File Existence & Recency
    if not result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Exported GPX file not found. Task failed."}
        
    task_start = result.get('task_start_time', 0)
    file_mtime = result.get('file_mtime', 0)
    
    if file_mtime >= task_start:
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("WARNING: File appears older than task start")

    # 2. Parse GPX File
    try:
        copy_from_env("C:\\workspace\\output\\campsite_location.gpx", temp_gpx.name)
        tree = ET.parse(temp_gpx.name)
        root = tree.getroot()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to parse exported GPX: {e}"}
    finally:
        for p in [temp_result.name, temp_gt.name, temp_gpx.name]:
            if os.path.exists(p):
                os.unlink(p)

    # BaseCamp exports use namespaces, e.g., xmlns="http://www.topografix.com/GPX/1/1"
    # We use tag endswith to safely ignore namespaces.
    wpts = [elem for elem in root.iter() if elem.tag.endswith('wpt')]
    trks = [elem for elem in root.iter() if elem.tag.endswith('trk')]
    
    # 3. Check Isolation (Only the waypoint was exported)
    if len(wpts) == 1 and len(trks) == 0:
        score += 10
        feedback_parts.append("Export isolated perfectly")
    else:
        feedback_parts.append(f"Export contained {len(wpts)} waypoints and {len(trks)} tracks (Expected exactly 1 waypoint, 0 tracks)")
        # Do not grant the 10 points if they exported everything.
        
    if len(wpts) == 0:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + " -> No waypoint found in export."}
        
    wpt = wpts[0]
    lat = float(wpt.attrib.get('lat', 0))
    lon = float(wpt.attrib.get('lon', 0))
    
    # 4. Check Waypoint Name
    name_elems = [elem for elem in wpt.iter() if elem.tag.endswith('name')]
    actual_name = name_elems[0].text if name_elems else ""
    
    if actual_name.strip() == expected_name:
        score += 10
        feedback_parts.append("Name correct")
    else:
        feedback_parts.append(f"Name incorrect (Got '{actual_name}', expected '{expected_name}')")

    # 5. Check Spatial Accuracy (Distance to Ground Truth Apex)
    distance = haversine(lat, lon, gt_lat, gt_lon)
    
    if distance <= thresholds['high_precision']:
        score += 70
        feedback_parts.append(f"High Precision: Placed {distance:.1f}m from actual apex")
    elif distance <= thresholds['medium_precision']:
        score += 50
        feedback_parts.append(f"Medium Precision: Placed {distance:.1f}m from apex")
    elif distance <= thresholds['low_precision']:
        score += 20
        feedback_parts.append(f"Low Precision: Placed {distance:.1f}m from apex")
    else:
        feedback_parts.append(f"Failed Precision: Waypoint placed {distance:.1f}m away (Too far off-trail)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "distance_meters": distance,
            "agent_lat": lat,
            "agent_lon": lon,
            "gt_lat": gt_lat,
            "gt_lon": gt_lon
        }
    }