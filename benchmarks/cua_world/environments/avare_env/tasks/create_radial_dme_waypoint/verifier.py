#!/usr/bin/env python3
import json
import os
import math
import logging
import tempfile
from typing import Dict, Any, List

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("verifier")

def calculate_distance(lat1, lon1, lat2, lon2):
    """
    Calculate the great circle distance between two points 
    on the earth (specified in decimal degrees)
    """
    # Convert decimal degrees to radians 
    lon1, lat1, lon2, lat2 = map(math.radians, [lon1, lat1, lon2, lat2])

    # Haversine formula 
    dlon = lon2 - lon1 
    dlat = lat2 - lat1 
    a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
    c = 2 * math.asin(math.sqrt(a)) 
    r = 3440.1 # Radius of earth in Nautical Miles
    return c * r

def parse_avare_plan(content: str) -> List[Dict[str, float]]:
    """
    Parses Avare plan content.
    Format is typically JSON array or line-based.
    Based on Avare source, Current.plan is often a JSON array of waypoints.
    """
    waypoints = []
    try:
        # Try JSON parsing first
        data = json.loads(content)
        if isinstance(data, list):
            for wp in data:
                # Avare JSON keys might vary, usually 'lat', 'lon', 'name', 'type'
                if 'lat' in wp and 'lon' in wp:
                    waypoints.append({
                        'lat': float(wp['lat']),
                        'lon': float(wp['lon']),
                        'name': wp.get('name', 'Unknown'),
                        'type': wp.get('type', '')
                    })
    except json.JSONDecodeError:
        # Fallback to simple line parsing if it's legacy CSV format
        # Type,ID,Name,Lat,Lon,Alt
        lines = content.split('\n')
        for line in lines:
            parts = line.split(',')
            if len(parts) >= 5:
                try:
                    waypoints.append({
                        'lat': float(parts[3]),
                        'lon': float(parts[4]),
                        'name': parts[2] if len(parts) > 2 else 'Unknown',
                        'id': parts[1] if len(parts) > 1 else 'Unknown'
                    })
                except ValueError:
                    continue
    return waypoints

def verify_create_radial_dme_waypoint(traj, env_info, task_info):
    """
    Verifies that a waypoint was created at SJC 320/15.
    Target Coordinates: Approx 37.566 N, 122.147 W
    """
    # Get environment copy function
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # Metadata
    metadata = task_info.get('metadata', {})
    target_lat = metadata.get('target_lat', 37.566)
    target_lon = metadata.get('target_lon', -122.147)
    tolerance = metadata.get('tolerance_deg', 0.05) # ~3 NM tolerance
    
    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Check 1: App running (10 pts)
    if result.get('app_running', False):
        score += 10
        feedback_parts.append("App is running")
    else:
        feedback_parts.append("App was closed")

    # Check 2: Plan file found (20 pts)
    plan_content = result.get('plan_content', "")
    if result.get('plan_found', False) and len(plan_content) > 5:
        score += 20
        feedback_parts.append("Flight plan created")
    else:
        feedback_parts.append("No active flight plan found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Check 3: Waypoint Analysis (70 pts)
    waypoints = parse_avare_plan(plan_content)
    
    if not waypoints:
        feedback_parts.append("Flight plan is empty")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    found_target = False
    closest_dist = float('inf')
    closest_wp = None

    for wp in waypoints:
        dist = calculate_distance(wp['lat'], wp['lon'], target_lat, target_lon)
        if dist < closest_dist:
            closest_dist = dist
            closest_wp = wp
    
    # Check if closest waypoint is within tolerance (approx 3 NM)
    # 0.05 degrees is approx 3 NM
    if closest_dist <= 3.0: # Nautical Miles
        score += 70
        found_target = True
        feedback_parts.append(f"Found waypoint matching SJC 320/15 (Dist: {closest_dist:.2f} NM)")
        if 'SJC' in closest_wp.get('name', '').upper() or '320' in closest_wp.get('name', ''):
            feedback_parts.append("Waypoint name looks correct")
    else:
        feedback_parts.append(f"No waypoint found near target. Closest was {closest_dist:.1f} NM away at ({closest_wp['lat']:.3f}, {closest_wp['lon']:.3f})")

    passed = score >= 90
    
    # Optional: VLM Verification (if we want to be fancy, but programmatic is strong here)
    # We rely primarily on programmatic plan inspection
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }