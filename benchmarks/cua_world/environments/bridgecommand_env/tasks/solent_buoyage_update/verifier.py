#!/usr/bin/env python3
import json
import os
import math
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_ini_objects(ini_content):
    """
    Parses Bridge Command INI content (indexed keys).
    Returns a list of dictionaries, e.g., [{'Type': 'Port', 'Lat': 50.1, ...}, ...]
    """
    objects = {}
    
    for line in ini_content.splitlines():
        line = line.strip()
        if not line or line.startswith(';'):
            continue
            
        # Match Key(Index)=Value or Key=Value
        # Regex for indexed keys: Param(123)=Value
        match = re.match(r'^(\w+)\((\d+)\)=(.*)$', line)
        if match:
            param = match.group(1)
            index = int(match.group(2))
            value = match.group(3).strip().replace('"', '')
            
            if index not in objects:
                objects[index] = {}
            
            try:
                objects[index][param] = float(value)
            except ValueError:
                objects[index][param] = value
                
    # Check for global 'Number' param to verify consistency
    global_number = 0
    match_global = re.search(r'^Number\s*=\s*(\d+)', ini_content, re.MULTILINE)
    if match_global:
        global_number = int(match_global.group(1))

    return [objects[i] for i in sorted(objects.keys())], global_number

def get_distance(lat1, lon1, lat2, lon2):
    """Euclidean distance in degrees (approximate is fine for this scale)"""
    return math.sqrt((lat1 - lat2)**2 + (lon1 - lon2)**2)

def verify_solent_buoyage_update(traj, env_info, task_info):
    """
    Verifies the Solent Buoyage Update task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Directory Creation (10 pts)
    if not result.get('dir_exists'):
        return {"passed": False, "score": 0, "feedback": "Target directory 'Solent_v2026' does not exist."}
    score += 10
    feedback_parts.append("Directory created")

    # 2. Check Description Update (5 pts)
    if result.get('desc_updated'):
        score += 5
        feedback_parts.append("World name updated")
    else:
        feedback_parts.append("World name NOT updated")

    # Load Ground Truth
    gt = result.get('ground_truth', {})
    if not gt:
        return {"passed": False, "score": 0, "feedback": "Verification failed: missing ground truth data."}

    # Parse INI files
    buoys, buoy_declared_count = parse_ini_objects(result.get('buoy_ini', ''))
    lights, light_declared_count = parse_ini_objects(result.get('light_ini', ''))

    # Tolerance for float comparison
    TOL = 0.001

    # 3. Verify Horse Sand Buoy Move (25 pts)
    hs_found = False
    for b in buoys:
        lat = b.get('Lat', 0)
        lon = b.get('Long', 0)
        dist = get_distance(lat, lon, gt['hs_new_lat'], gt['hs_new_lon'])
        
        # Check if this looks like the Horse Sand buoy (SafeWater or near target)
        if dist < TOL:
            hs_found = True
            break
            
    if hs_found:
        score += 25
        feedback_parts.append("Horse Sand buoy moved correctly")
    else:
        feedback_parts.append(f"Horse Sand buoy NOT found at new coords {gt['hs_new_lat']:.4f}, {gt['hs_new_lon']:.4f}")

    # 4. Verify Wreck Buoy Addition (25 pts)
    wreck_found = False
    for b in buoys:
        lat = b.get('Lat', 0)
        lon = b.get('Long', 0)
        dist = get_distance(lat, lon, gt['wreck_lat'], gt['wreck_lon'])
        
        if dist < TOL:
            wreck_found = True
            # Optional: check type
            b_type = str(b.get('Type', '')).lower()
            if 'wreck' in b_type:
                score += 5 # Bonus for correct type naming
            break
            
    if wreck_found:
        score += 20
        feedback_parts.append("Wreck buoy added correctly")
    else:
        feedback_parts.append(f"Wreck buoy NOT found at {gt['wreck_lat']:.4f}, {gt['wreck_lon']:.4f}")

    # 5. Verify Light Move (25 pts)
    light_found = False
    for l in lights:
        lat = l.get('Lat', 0)
        lon = l.get('Long', 0)
        dist = get_distance(lat, lon, gt['hs_new_lat'], gt['hs_new_lon'])
        
        if dist < TOL:
            light_found = True
            break
            
    if light_found:
        score += 25
        feedback_parts.append("Light moved correctly")
    else:
        feedback_parts.append("Light NOT moved to new buoy position")

    # 6. Verify INI Integrity (10 pts)
    # Check if 'Number=' matches the actual number of objects parsed
    if buoy_declared_count == len(buoys) and buoy_declared_count > 0:
        score += 5
    else:
        feedback_parts.append(f"buoy.ini Number mismatch (Declared: {buoy_declared_count}, Found: {len(buoys)})")

    if light_declared_count == len(lights) and light_declared_count > 0:
        score += 5
    else:
        feedback_parts.append(f"light.ini Number mismatch (Declared: {light_declared_count}, Found: {len(lights)})")

    # Cap bonus points
    score = min(score, 100)
    
    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }