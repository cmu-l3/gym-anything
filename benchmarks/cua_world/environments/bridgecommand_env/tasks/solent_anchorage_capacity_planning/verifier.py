#!/usr/bin/env python3
import json
import math
import base64
import re
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_solent_anchorage(traj, env_info, task_info):
    """
    Verifies that the agent has placed ships within bounds and without overlapping swing circles.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function unavailable"}

    # 1. Load Metadata
    metadata = task_info.get('metadata', {})
    ships_meta = metadata.get('ships', [])
    bounds = metadata.get('zone_bounds', {})
    buffer_nm = metadata.get('buffer_nm', 0.15)
    swing_mult = metadata.get('swing_multiplier', 1.5)

    # 2. Retrieve Result from Container
    import tempfile
    local_result = tempfile.mktemp()
    try:
        copy_from_env("/tmp/task_result.json", local_result)
        with open(local_result, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(local_result):
            os.remove(local_result)

    # 3. Basic File Checks (20 points)
    score = 0
    feedback = []
    
    if not result.get("scenario_exists"):
        return {"passed": False, "score": 0, "feedback": "Scenario directory not created."}
    
    if not result.get("othership_exists"):
        return {"passed": False, "score": 0, "feedback": "othership.ini file missing."}
        
    if not result.get("created_during_task"):
         return {"passed": False, "score": 0, "feedback": "Files were not modified during the task session."}

    score += 10 # Files exist
    feedback.append("Scenario files created.")

    # 4. Parse Environment (10 points)
    env_content = base64.b64decode(result.get("environment_content_b64", "")).decode('utf-8', errors='ignore')
    if "Weather=5" in env_content or "Weather=5.0" in env_content or "Weather=6" in env_content:
        score += 10
        feedback.append("Weather configured correctly (Stormy).")
    else:
        feedback.append("Weather setting missing or not stormy (expected Weather=5.0).")

    # 5. Parse Ship Positions (othership.ini)
    othership_content = base64.b64decode(result.get("othership_content_b64", "")).decode('utf-8', errors='ignore')
    
    # Simple INI parser for 'Key(Index)=Value' format
    # We look for InitLat(N)=... and InitLong(N)=...
    parsed_ships = {}
    
    # Normalize content
    lines = othership_content.splitlines()
    for line in lines:
        line = line.strip()
        if not line or line.startswith('//'): continue
        
        # Regex to match Key(Index)=Value
        match = re.match(r'([A-Za-z]+)\((\d+)\)=(.*)', line)
        if match:
            key, idx, val = match.groups()
            idx = int(idx)
            if idx not in parsed_ships: parsed_ships[idx] = {}
            parsed_ships[idx][key] = val

    # Verify Count
    agent_ship_count = len(parsed_ships)
    expected_count = len(ships_meta)
    
    if agent_ship_count != expected_count:
        feedback.append(f"Incorrect vessel count. Found {agent_ship_count}, expected {expected_count}.")
        # Penalize but continue to check what IS there
    else:
        score += 10
        feedback.append(f"Correct vessel count ({expected_count}).")

    # 6. Geometric Validation (70 points)
    # 6a. Bounds Check (30 points)
    bounds_valid = True
    vessels_processed = []

    for idx, data in parsed_ships.items():
        try:
            lat = float(data.get('InitLat', -999))
            lon = float(data.get('InitLong', -999))
            
            # Check valid parsing
            if lat == -999 or lon == -999:
                feedback.append(f"Vessel {idx}: Could not parse Lat/Long.")
                bounds_valid = False
                continue

            # Check bounds
            if not (bounds['min_lat'] <= lat <= bounds['max_lat']):
                feedback.append(f"Vessel {idx}: Lat {lat} out of bounds ({bounds['min_lat']}-{bounds['max_lat']}).")
                bounds_valid = False
            
            if not (bounds['min_long'] <= lon <= bounds['max_long']): # Note: West is usually negative
                feedback.append(f"Vessel {idx}: Long {lon} out of bounds ({bounds['min_long']}-{bounds['max_long']}).")
                bounds_valid = False

            # Assign to a ship model (heuristic: simple order mapping or just generic validation)
            # Since we can't easily map agent's indices to specific named ships without parsing 'Type',
            # we will assume the agent followed the list order OR check if the set of radii fits.
            # To be lenient, we'll map index 1->1, 2->2 etc from the task list.
            
            # Map index to meta list (0-based in list, 1-based in INI usually)
            meta_idx = idx - 1
            if 0 <= meta_idx < len(ships_meta):
                length = ships_meta[meta_idx]['length_m']
                # Calculate Safety Radius in NM
                radius_nm = (length * swing_mult / 1852.0) + buffer_nm
                vessels_processed.append({'id': idx, 'lat': lat, 'lon': lon, 'r': radius_nm})
            else:
                # Fallback for extra indices
                vessels_processed.append({'id': idx, 'lat': lat, 'lon': lon, 'r': 0.3}) # Default fallback

        except ValueError:
            feedback.append(f"Vessel {idx}: Invalid coordinate format.")
            bounds_valid = False

    if bounds_valid and len(vessels_processed) > 0:
        score += 30
        feedback.append("All vessels within anchorage zone boundaries.")
    else:
        feedback.append("One or more vessels are outside the designated zone.")

    # 6b. Separation/Overlap Check (40 points)
    # Haversine distance or Equirectangular approximation (fine for small distance)
    # 1 deg Lat = 60 NM
    # 1 deg Long = 60 * cos(lat) NM
    collisions = 0
    
    avg_lat = (bounds['min_lat'] + bounds['max_lat']) / 2.0
    lat_scale = 60.0
    lon_scale = 60.0 * math.cos(math.radians(avg_lat))

    for i in range(len(vessels_processed)):
        for j in range(i + 1, len(vessels_processed)):
            v1 = vessels_processed[i]
            v2 = vessels_processed[j]

            d_lat = abs(v1['lat'] - v2['lat']) * lat_scale
            d_lon = abs(v1['lon'] - v2['lon']) * lon_scale
            dist_nm = math.sqrt(d_lat**2 + d_lon**2)

            required_dist = v1['r'] + v2['r']
            
            if dist_nm < required_dist:
                collisions += 1
                feedback.append(f"COLLISION RISK: Vessel {v1['id']} and {v2['id']} overlap! (Dist: {dist_nm:.3f}nm, Req: {required_dist:.3f}nm)")

    if len(vessels_processed) < 2:
        feedback.append("Not enough vessels to check separation.")
    elif collisions == 0:
        score += 40
        feedback.append("All vessels have safe separation distances.")
    else:
        feedback.append(f"FAILED: {collisions} unsafe overlaps detected.")

    # Final tally
    passed = (score >= 90) # Strict pass for safety critical tasks
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }