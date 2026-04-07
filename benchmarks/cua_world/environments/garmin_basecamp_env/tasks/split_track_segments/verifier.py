#!/usr/bin/env python3
"""
Verifier for split_track_segments task.

Verification Strategy:
1. Validates presence and timestamps of the exported GPX files to detect "do nothing" attacks.
2. Parses GPX XML structure to verify `<name>` tags correspond to expected segment names.
3. Examines the extracted coordinates to evaluate splitting thresholds and geographic continuity.
4. Ensures neither file is an identical duplicate (bypassing the split workflow).
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
    """Calculates the great-circle distance between two points on the Earth's surface."""
    R = 6371000  # radius of Earth in meters
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)
    
    a = math.sin(delta_phi / 2.0)**2 + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2.0)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c

def parse_gpx_track(filepath):
    """Parses a GPX file and extracts the `<trk>` name and a sequence of its `<trkpt>` coordinates."""
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        def strip_ns(tag):
            return tag.split('}')[-1] if '}' in tag else tag

        name = ""
        # Drill specifically into track name to avoid global file metadata names
        for trk in root.iter():
            if strip_ns(trk.tag) == 'trk':
                for elem in trk.iter():
                    if strip_ns(elem.tag) == 'name':
                        if elem.text:
                            name = elem.text
                        break
                break
                
        points = []
        for elem in root.iter():
            if strip_ns(elem.tag) == 'trkpt':
                lat = float(elem.attrib.get('lat', 0))
                lon = float(elem.attrib.get('lon', 0))
                points.append((lat, lon))
        
        return {"valid": True, "name": name, "points": points}
    except Exception as e:
        return {"valid": False, "error": str(e)}

def verify_split_track(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    metadata = task_info.get('metadata', {})
    expected_north_name = metadata.get('expected_north_name', 'Fells North Segment').lower()
    expected_south_name = metadata.get('expected_south_name', 'Fells South Segment').lower()
    min_points = metadata.get('min_segment_points', 10)
    continuity_tol = metadata.get('continuity_tolerance_meters', 500)
    
    score = 0
    feedback = []
    
    # 1. Retrieve the task_result.json structured metadata
    tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", tmp_result.name)
        with open(tmp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result metadata: {e}"}
    finally:
        if os.path.exists(tmp_result.name):
            os.unlink(tmp_result.name)
            
    north_exists = result.get('north_exists', False)
    south_exists = result.get('south_exists', False)
    start_time = result.get('task_start_time', 0)
    north_mtime = result.get('north_mtime', 0)
    south_mtime = result.get('south_mtime', 0)
    orig_count = result.get('original_point_count', 0)
    
    if not north_exists and not south_exists:
        return {"passed": False, "score": 0, "feedback": "Neither expected GPX output file exists."}
        
    # Anti-gaming checks: Verify output files were created during execution window
    created_during_task = True
    if north_exists and north_mtime < start_time:
        created_during_task = False
    if south_exists and south_mtime < start_time:
        created_during_task = False
        
    if not created_during_task:
        feedback.append("WARNING: GPX files were modified before the task started (anti-gaming trip).")
        
    # 2. Retrieve and parse the exported GPX files from the environment
    north_data = {"valid": False, "points": [], "name": ""}
    if north_exists:
        tmp_n = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
        try:
            copy_from_env("C:\\workspace\\fells_north.gpx", tmp_n.name)
            north_data = parse_gpx_track(tmp_n.name)
            if north_data["valid"]:
                score += 10
                feedback.append("North file correctly formatted GPX.")
            else:
                feedback.append(f"North file invalid structure: {north_data.get('error')}")
        finally:
            if os.path.exists(tmp_n.name): os.unlink(tmp_n.name)
            
    south_data = {"valid": False, "points": [], "name": ""}
    if south_exists:
        tmp_s = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
        try:
            copy_from_env("C:\\workspace\\fells_south.gpx", tmp_s.name)
            south_data = parse_gpx_track(tmp_s.name)
            if south_data["valid"]:
                score += 10
                feedback.append("South file correctly formatted GPX.")
            else:
                feedback.append(f"South file invalid structure: {south_data.get('error')}")
        finally:
            if os.path.exists(tmp_s.name): os.unlink(tmp_s.name)

    if not north_data["valid"] or not south_data["valid"]:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}
        
    # 3. GPX Track Content Analysis
    # A. Names check
    if north_data["name"].strip().lower() == expected_north_name:
        score += 10
        feedback.append("North segment accurately named.")
    else:
        feedback.append(f"North segment improperly named: '{north_data['name']}'")
        
    if south_data["name"].strip().lower() == expected_south_name:
        score += 10
        feedback.append("South segment accurately named.")
    else:
        feedback.append(f"South segment improperly named: '{south_data['name']}'")
        
    # B. Points count thresholds (empty files aren't true tracks)
    n_pts = len(north_data["points"])
    s_pts = len(south_data["points"])
    
    if n_pts >= min_points and s_pts >= min_points:
        score += 10
        feedback.append(f"Segments have valid coordinate density (North: {n_pts}, South: {s_pts}).")
    else:
        feedback.append(f"Segments lack coordinate density (North: {n_pts}, South: {s_pts}).")
        
    # C. Conservation of Track Coverage Check
    if orig_count > 0:
        diff = abs((n_pts + s_pts) - orig_count)
        if diff <= (orig_count * 0.15):  # allow +/-15% overlap
            score += 15
            feedback.append("Combined coordinate density matches expected baseline.")
        else:
            feedback.append(f"Disproportionate coordinate retention. Orig: {orig_count}, Combined: {n_pts + s_pts}")
            
    # D. Balanced Splitting
    if n_pts > 0 and s_pts > 0:
        total = n_pts + s_pts
        if n_pts <= (total * 0.75) and s_pts <= (total * 0.75):
            score += 10
            feedback.append("Track was split near the middle.")
        else:
            feedback.append("Track split is grossly asymmetric.")
            
    # E. Geographic Continuity Check
    if n_pts > 0 and s_pts > 0:
        last_n = north_data["points"][-1]
        first_s = south_data["points"][0]
        dist = haversine(last_n[0], last_n[1], first_s[0], first_s[1])
        if dist <= continuity_tol:
            score += 10
            feedback.append(f"Geographic continuity preserved (gap: {dist:.1f}m).")
        else:
            feedback.append(f"Disjoint segments (gap: {dist:.1f}m exceeds {continuity_tol}m).")
            
    # F. Distinct Data Integrity
    if n_pts > 0 and s_pts > 0 and north_data["points"] != south_data["points"]:
        score += 5
        feedback.append("Segment coordinate signatures are appropriately distinct.")
    else:
        feedback.append("North and South segments share identically duplicated points.")

    if created_during_task:
        score += 10
        
    # Success definition 
    key_criteria_met = (north_data["valid"] and south_data["valid"] and created_during_task and n_pts >= min_points and s_pts >= min_points)
    passed = score >= 65 and key_criteria_met
    
    return {
        "passed": bool(passed),
        "score": score,
        "feedback": " | ".join(feedback)
    }