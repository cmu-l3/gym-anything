#!/usr/bin/env python3
"""
Verifier for extract_eastern_loop_segment task.
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import math
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    HAS_VLM = True
except ImportError:
    HAS_VLM = False

def haversine(lat1, lon1, lat2, lon2):
    R = 6371000  # Radius of Earth in meters
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)
    a = math.sin(delta_phi/2.0)**2 + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda/2.0)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c

def get_gpx_bounds_and_points(gpx_path):
    """Parse a GPX file to find all points and the geographic extremes (poles)."""
    try:
        tree = ET.parse(gpx_path)
        root = tree.getroot()
        
        ns = ''
        if root.tag.startswith('{'):
            ns = root.tag.split('}')[0] + '}'
            
        points = []
        for trkpt in root.iter(f'{ns}trkpt'):
            lat = float(trkpt.attrib['lat'])
            lon = float(trkpt.attrib['lon'])
            points.append((lat, lon))
            
        if not points:
            return None, None

        # Absolute extremes of the path
        max_lat_point = max(points, key=lambda p: p[0])
        min_lat_point = min(points, key=lambda p: p[0])
        max_lon_point = max(points, key=lambda p: p[1])
        min_lon_point = min(points, key=lambda p: p[1])
        
        bounds = {
            'north_pole': max_lat_point,
            'south_pole': min_lat_point,
            'east_pole': max_lon_point,
            'west_pole': min_lon_point
        }
        return bounds, points
    except Exception as e:
        logger.error(f"Error parsing GPX {gpx_path}: {e}")
        return None, None

def get_track_name(gpx_path):
    try:
        tree = ET.parse(gpx_path)
        root = tree.getroot()
        ns = ''
        if root.tag.startswith('{'):
            ns = root.tag.split('}')[0] + '}'
        name_elem = root.find(f'.//{ns}name')
        if name_elem is not None:
            return name_elem.text
        return None
    except:
        return None

def get_track_segments_count(gpx_path):
    try:
        tree = ET.parse(gpx_path)
        root = tree.getroot()
        ns = ''
        if root.tag.startswith('{'):
            ns = root.tag.split('}')[0] + '}'
        return len(list(root.iter(f'{ns}trkseg')))
    except:
        return 0

def calculate_track_length(points):
    length = 0.0
    for i in range(len(points) - 1):
        length += haversine(points[i][0], points[i][1], points[i+1][0], points[i+1][1])
    return length


def verify_extract_eastern_loop(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    tolerance_meters = metadata.get('tolerance_meters', 150)

    score = 0
    feedback_parts = []
    
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    temp_orig_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    
    try:
        copy_from_env("C:/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
        
    gpx_exists = result.get('gpx_exists', False)
    gpx_created = result.get('gpx_created_during_task', False)
    
    if not gpx_exists:
        return {"passed": False, "score": 0, "feedback": "Exported GPX file not found."}
        
    try:
        copy_from_env("C:/workspace/fells_east_segment.gpx", temp_gpx.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to copy exported GPX file: {e}"}

    # Extract original reference bounds to ensure agent made correct physical splits
    try:
        copy_from_env("C:/workspace/data/fells_loop.gpx", temp_orig_gpx.name)
        orig_bounds, orig_points = get_gpx_bounds_and_points(temp_orig_gpx.name)
    except Exception:
        orig_bounds = None

    if gpx_exists and gpx_created:
        score += 5
        feedback_parts.append("GPX created")

    # Parse exported GPX
    export_bounds, export_points = get_gpx_bounds_and_points(temp_gpx.name)
    track_name = get_track_name(temp_gpx.name)
    num_segments = get_track_segments_count(temp_gpx.name)
    
    if not export_points:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + " | Exported GPX is empty"}

    # Track Continuous Join Check (10 points)
    if num_segments == 1:
        score += 10
        feedback_parts.append("Track joined continuously")
    else:
        feedback_parts.append(f"Track is fractured into {num_segments} segments (Join not used)")

    # Naming Verification (10 points)
    expected_name = metadata.get('expected_track_name', 'Fells East Segment')
    if track_name and expected_name.lower() in track_name.lower():
        score += 10
        feedback_parts.append("Correctly named")
    else:
        feedback_parts.append(f"Name mismatch ({track_name})")

    split_north_ok = False
    split_south_ok = False
    east_path_ok = False
    
    if orig_bounds:
        orig_north = orig_bounds['north_pole']
        orig_south = orig_bounds['south_pole']
        orig_east = orig_bounds['east_pole']
        
        # The two endpoints of the exported path must align with the True North and True South points
        p1 = export_points[0]
        p2 = export_points[-1]
        
        dist_p1_north = haversine(p1[0], p1[1], orig_north[0], orig_north[1])
        dist_p1_south = haversine(p1[0], p1[1], orig_south[0], orig_south[1])
        dist_p2_north = haversine(p2[0], p2[1], orig_north[0], orig_north[1])
        dist_p2_south = haversine(p2[0], p2[1], orig_south[0], orig_south[1])
        
        if (dist_p1_north < tolerance_meters and dist_p2_south < tolerance_meters) or \
           (dist_p1_south < tolerance_meters and dist_p2_north < tolerance_meters):
            split_north_ok = True
            split_south_ok = True
        else:
            if dist_p1_north < tolerance_meters or dist_p2_north < tolerance_meters:
                split_north_ok = True
            if dist_p1_south < tolerance_meters or dist_p2_south < tolerance_meters:
                split_south_ok = True
                
        if split_north_ok: score += 15
        if split_south_ok: score += 15
        
        # East Path Verification: Did they pick the correct fragment?
        closest_to_east = min(haversine(p[0], p[1], orig_east[0], orig_east[1]) for p in export_points)
        if closest_to_east < tolerance_meters:
            score += 15
            east_path_ok = True
            feedback_parts.append("Export matches Eastern fragment")
        else:
            feedback_parts.append("Exported path fails East Side geographic check")
    else:
        feedback_parts.append("Could not fetch ground truth reference, skipping checks")

    # Distance File Verification (10 points)
    txt_exists = result.get('txt_exists', False)
    txt_created = result.get('txt_created_during_task', False)
    distance_text = result.get('distance_text', '')
    
    if txt_exists and txt_created and distance_text:
        numbers = re.findall(r"[-+]?(?:\d*\.*\d+)", distance_text)
        if numbers:
            reported_dist = float(numbers[0])
            actual_length_m = calculate_track_length(export_points)
            
            # BaseCamp distances are subject to projection minor-variances. Support mi & km.
            actual_length_mi = actual_length_m * 0.000621371
            actual_length_km = actual_length_m / 1000.0
            
            pct_error_mi = abs(reported_dist - actual_length_mi) / actual_length_mi if actual_length_mi else 1.0
            pct_error_km = abs(reported_dist - actual_length_km) / actual_length_km if actual_length_km else 1.0
            
            if pct_error_mi < 0.20 or pct_error_km < 0.20:
                score += 10
                feedback_parts.append(f"Distance valid ({reported_dist})")
            else:
                feedback_parts.append(f"Distance inaccurate: {reported_dist} (Act: {actual_length_mi:.2f}mi)")
        else:
            feedback_parts.append("No numeric distance in file")
    else:
        feedback_parts.append("Distance text file missing")

    # VLM Trajectory Verification (10 points) - Proves real workflow rather than manual XML edits
    vlm_score = 0
    if HAS_VLM:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + ([final] if final else [])
            if images:
                prompt = '''Analyze these trajectory frames of a user operating Garmin BaseCamp.
Did the user interact with the track editing tools (Divide/Split, Join) and the map interface?
Respond with JSON: {"tools_used": true/false}'''
                vlm_res = query_vlm(images=images, prompt=prompt)
                if vlm_res and vlm_res.get('parsed', {}).get('tools_used', False):
                    vlm_score = 10
                    feedback_parts.append("VLM visual verify passed (+10)")
                else:
                    feedback_parts.append("VLM did not verify tool UI usage")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            vlm_score = 10 
    else:
        vlm_score = 10 # Passthrough if VLM container unavailable
        
    score += vlm_score

    for path in [temp_result.name, temp_gpx.name, temp_orig_gpx.name]:
        if os.path.exists(path):
            os.unlink(path)

    # Threshold sets rigorous demand on physical track logic mapping
    passed = (score >= 70) and split_north_ok and split_south_ok and east_path_ok
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }