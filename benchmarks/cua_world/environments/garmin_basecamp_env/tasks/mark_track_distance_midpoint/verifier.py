#!/usr/bin/env python3
"""
Verifier for mark_track_distance_midpoint task.

VERIFICATION METRICS:
1. Output exists & anti-gaming verification
2. Programmatic validation of the GPX BaseCamp XML signature
3. Geometric accuracy calculation by independently walking the fells_loop track nodes
4. Correctness of property edits (Name and Description/Notes)
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def haversine(lat1, lon1, lat2, lon2):
    """Calculate the great circle distance between two points on the earth."""
    R = 6371000 # radius in meters
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)
    a = math.sin(delta_phi/2.0)**2 + math.cos(phi1)*math.cos(phi2)*math.sin(delta_lambda/2.0)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R * c

def get_midpoint(gpx_path):
    """Calculates true accumulative-distance midpoint of the GPX track polyline."""
    try:
        tree = ET.parse(gpx_path)
        root = tree.getroot()
        points = []
        for trkpt in root.findall('.//{*}trkpt'):
            lat = float(trkpt.attrib['lat'])
            lon = float(trkpt.attrib['lon'])
            points.append((lat, lon))
        
        if not points:
            return None
            
        distances = [0.0]
        for i in range(1, len(points)):
            dist = haversine(points[i-1][0], points[i-1][1], points[i][0], points[i][1])
            distances.append(distances[-1] + dist)
            
        total_dist = distances[-1]
        mid_dist = total_dist / 2.0
        
        for i in range(len(distances)):
            if distances[i] >= mid_dist:
                if i == 0:
                    return points[0]
                d1 = mid_dist - distances[i-1]
                d2 = distances[i] - mid_dist
                # Return the closest node to exact mathematical midpoint
                if d1 < d2:
                    return points[i-1]
                else:
                    return points[i]
        return points[-1]
    except Exception as e:
        logger.error(f"Error parsing track GPX: {e}")
        return None

def parse_agent_gpx(gpx_path):
    """Parses agent's GPX file and validates UI signature."""
    try:
        tree = ET.parse(gpx_path)
        root = tree.getroot()
        
        with open(gpx_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        
        # Verify the file was exported by Garmin engine (anti-gaming check)
        has_gpxx = 'GpxExtensions' in content or 'gpxx' in content
        
        wpt = root.find('.//{*}wpt')
        if wpt is None:
            return {"exists": False}
            
        lat = float(wpt.attrib.get('lat', 0))
        lon = float(wpt.attrib.get('lon', 0))
        
        name_el = wpt.find('.//{*}name')
        name = name_el.text if name_el is not None else ""
        
        desc_el = wpt.find('.//{*}desc')
        desc = desc_el.text if desc_el is not None else ""
        
        # BaseCamp sometimes puts notes inside <cmt> based on version
        if not desc:
            cmt_el = wpt.find('.//{*}cmt')
            if cmt_el is not None and cmt_el.text:
                desc = cmt_el.text
        
        return {
            "exists": True,
            "lat": lat,
            "lon": lon,
            "name": name,
            "desc": desc,
            "has_gpxx": has_gpxx
        }
    except Exception as e:
        logger.error(f"Error parsing agent GPX: {e}")
        return {"exists": False}

def verify_mark_track_distance_midpoint(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', 'Lunch_Stop')
    expected_notes = metadata.get('expected_notes', 'Halfway rest point')
    
    score = 0
    feedback_parts = []
    
    # 1. Read exported validation JSON from the environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Error reading task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Task result file not found or invalid"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    if not result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file lunch_stop.gpx was not created"}
        
    score += 10
    feedback_parts.append("File created")
    
    if not result.get('file_created_during_task', False):
        feedback_parts.append("WARNING: File was not created during the task window")
        
    if result.get('app_was_running', False):
        feedback_parts.append("BaseCamp running")
        
    # 2. Retrieve and analyze original fells_loop track data to find truth midpoint
    temp_track = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    midpoint = None
    try:
        copy_from_env("C:\\workspace\\data\\fells_loop.gpx", temp_track.name)
        midpoint = get_midpoint(temp_track.name)
    except Exception as e:
        logger.error(f"Error reading track GPX: {e}")
    finally:
        if os.path.exists(temp_track.name):
            os.unlink(temp_track.name)
            
    if not midpoint:
        return {"passed": False, "score": score, "feedback": "Verifier Error: Failed to calculate true midpoint from track"}
        
    # 3. Retrieve and analyze the agent's exported file
    temp_agent = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    agent_data = {"exists": False}
    try:
        copy_from_env("C:\\workspace\\output\\lunch_stop.gpx", temp_agent.name)
        agent_data = parse_agent_gpx(temp_agent.name)
    except Exception as e:
        logger.error(f"Error reading agent GPX: {e}")
    finally:
        if os.path.exists(temp_agent.name):
            os.unlink(temp_agent.name)
            
    if not agent_data["exists"]:
        feedback_parts.append("Valid Waypoint not found in exported file")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    # Verify Garmin signature
    if agent_data["has_gpxx"]:
        score += 20
        feedback_parts.append("BaseCamp signature present")
    else:
        feedback_parts.append("Missing BaseCamp GPX extensions (Likely spoofed file)")
        
    # Verify Naming
    if expected_name.lower() in agent_data["name"].lower():
        score += 10
        feedback_parts.append("Name correct")
    else:
        feedback_parts.append(f"Name incorrect: '{agent_data['name']}'")
        
    # Verify Notes
    if expected_notes.lower() in agent_data["desc"].lower():
        score += 10
        feedback_parts.append("Notes correct")
    else:
        feedback_parts.append("Notes incorrect or missing")
        
    # Verify Accuracy
    dist = haversine(midpoint[0], midpoint[1], agent_data["lat"], agent_data["lon"])
    if dist <= 50:
        score += 50
        feedback_parts.append(f"High accuracy (dist: {dist:.1f}m)")
    elif dist <= 200:
        score += 25
        feedback_parts.append(f"Partial accuracy (dist: {dist:.1f}m)")
    else:
        feedback_parts.append(f"Poor accuracy (dist: {dist:.1f}m, expected: ~{midpoint[0]:.4f}, {midpoint[1]:.4f})")
        
    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }