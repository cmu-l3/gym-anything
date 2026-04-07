#!/usr/bin/env python3
"""
Verifier for Radar Calibration Array Task.

This script verifies that the agent has created a mathematically accurate
scenario with targets placed at precise geodesic coordinates.

Key Verification Logic:
1. Calculates distance and bearing from Ownship to each Target.
2. Checks North/South targets (Latitude check).
3. Checks East/West targets (Longitude check with Departure formula).
4. Verifies vessel types match the cardinal directions.
"""

import json
import math
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def calculate_geodesic_distance_bearing(lat1, lon1, lat2, lon2):
    """
    Calculate distance (nm) and bearing (degrees) between two points.
    Using spherical approximation which is sufficient for <20nm.
    
    1 nm = 1852 meters.
    1 degree lat ~= 60 nm.
    1 degree lon ~= 60 * cos(lat) nm.
    """
    # Convert to radians
    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    lon1_rad = math.radians(lon1)
    lon2_rad = math.radians(lon2)
    
    # Delta lat/lon
    d_lat = lat2 - lat1  # degrees
    d_lon = lon2 - lon1  # degrees
    
    # Mean latitude for Departure calculation
    mean_lat_rad = (lat1_rad + lat2_rad) / 2.0
    
    # Distance components in Nautical Miles
    dist_ns = d_lat * 60.0
    dist_ew = d_lon * 60.0 * math.cos(mean_lat_rad)
    
    # Total Distance
    dist_nm = math.sqrt(dist_ns**2 + dist_ew**2)
    
    # Bearing (standard nav bearing: 0 is North, 90 East)
    # atan2(y, x) returns radians from -pi to pi
    # y = East/West component, x = North/South component
    bearing_rad = math.atan2(dist_ew, dist_ns)
    bearing_deg = math.degrees(bearing_rad)
    
    if bearing_deg < 0:
        bearing_deg += 360.0
        
    return dist_nm, bearing_deg

def verify_radar_calibration_array(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    metadata = task_info.get('metadata', {})
    center_lat = metadata.get('center_lat', 50.4)
    center_long = metadata.get('center_long', -1.5)
    target_ranges = metadata.get('ranges_nm', [2.0, 4.0, 6.0, 8.0, 10.0])
    tolerance = metadata.get('tolerance_nm', 0.1)

    # Copy result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Criterion 1: Scenario Existence (10 pts) ---
    if not result.get("scenario_exists"):
        return {"passed": False, "score": 0, "feedback": "Scenario directory created."}
    
    if all(result.get("files", {}).values()):
        score += 10
        feedback.append("Scenario files created.")
    else:
        feedback.append("Missing some INI files.")

    # --- Criterion 2: Ownship Configuration (10 pts) ---
    ownship = result.get("ownship", {})
    try:
        own_lat = float(ownship.get("initiallat", -999))
        own_long = float(ownship.get("initiallong", -999))
        
        # Check if coordinates match requirement (50.4N, 1.5W)
        if abs(own_lat - center_lat) < 0.001 and abs(own_long - center_long) < 0.001:
            score += 10
            feedback.append("Ownship positioned correctly.")
        else:
            feedback.append(f"Ownship position incorrect: {own_lat}, {own_long} (Expected {center_lat}, {center_long})")
    except ValueError:
        feedback.append("Could not parse ownship coordinates.")
        own_lat, own_long = center_lat, center_long # Fallback for relative checks

    # --- Criterion 3: Target Verification (60 pts) ---
    otherships = result.get("otherships", [])
    
    if len(otherships) != 20:
        feedback.append(f"Found {len(otherships)} targets (Expected 20).")
    
    # Buckets for each direction
    legs = {"North": [], "East": [], "South": [], "West": []}
    
    for ship in otherships:
        try:
            s_lat = float(ship.get("initiallat", 0))
            s_long = float(ship.get("initiallong", 0))
            s_type = ship.get("type", "").lower()
            
            dist, bearing = calculate_geodesic_distance_bearing(own_lat, own_long, s_lat, s_long)
            
            # Categorize by bearing
            if 350 <= bearing or bearing <= 10:
                legs["North"].append((dist, s_type))
            elif 80 <= bearing <= 100:
                legs["East"].append((dist, s_type))
            elif 170 <= bearing <= 190:
                legs["South"].append((dist, s_type))
            elif 260 <= bearing <= 280:
                legs["West"].append((dist, s_type))
                
        except ValueError:
            continue

    # Evaluate North/South (Lat check - Easier)
    ns_correct_count = 0
    for direction in ["North", "South"]:
        leg_ships = sorted(legs[direction], key=lambda x: x[0])
        # Check if we have ships at approximately correct ranges
        valid_ranges_found = 0
        for r in target_ranges:
            # Find closest ship
            if not leg_ships: break
            closest = min(leg_ships, key=lambda x: abs(x[0] - r))
            if abs(closest[0] - r) <= tolerance:
                valid_ranges_found += 1
        
        if valid_ranges_found >= 4: # Allow 1 missing
            ns_correct_count += 1
            
    if ns_correct_count == 2:
        score += 20
        feedback.append("North/South target geometry correct.")
    elif ns_correct_count == 1:
        score += 10
        feedback.append("Partial North/South geometry correct.")
    else:
        feedback.append("North/South geometry incorrect.")

    # Evaluate East/West (Long check - Math heavy)
    ew_correct_count = 0
    for direction in ["East", "West"]:
        leg_ships = sorted(legs[direction], key=lambda x: x[0])
        valid_ranges_found = 0
        
        # Check for the naive error (assuming 1 min long = 1 nm)
        # At 50.4N, factor is ~0.637. Naive error results in distance being ~63% of expected.
        naive_error_detected = False
        
        for r in target_ranges:
            if not leg_ships: break
            closest = min(leg_ships, key=lambda x: abs(x[0] - r))
            
            # Check correctness
            if abs(closest[0] - r) <= tolerance:
                valid_ranges_found += 1
            elif abs(closest[0] - (r * 0.637)) < 0.2:
                naive_error_detected = True
        
        if valid_ranges_found >= 4:
            ew_correct_count += 1
        elif naive_error_detected:
            feedback.append(f"{direction} leg shows Departure error (Long calculation didn't account for Latitude scaling).")

    if ew_correct_count == 2:
        score += 40
        feedback.append("East/West target geometry correct (Departure math validated).")
    elif ew_correct_count == 1:
        score += 20
        feedback.append("Partial East/West geometry correct.")
    else:
        feedback.append("East/West geometry incorrect.")

    # --- Criterion 4: Vessel Types (10 pts) ---
    # Check simple keywords in the buckets
    type_score = 0
    
    # North: Steel/Tanker/Cargo
    if any("tanker" in s[1] or "cargo" in s[1] or "container" in s[1] for s in legs["North"]):
        type_score += 2.5
    # East: GRP/Yacht
    if any("yacht" in s[1] or "motor" in s[1] or "grp" in s[1] for s in legs["East"]):
        type_score += 2.5
    # South: Wood/Fishing
    if any("fish" in s[1] or "trawler" in s[1] or "wood" in s[1] for s in legs["South"]):
        type_score += 2.5
    # West: Buoy
    if any("buoy" in s[1] or "mark" in s[1] for s in legs["West"]):
        type_score += 2.5
        
    if type_score >= 10:
        score += 10
        feedback.append("Vessel types mapped correctly.")
    else:
        score += type_score
        feedback.append(f"Vessel types partially correct ({type_score}/10).")
        
    # --- Criterion 5: Environment (10 pts) ---
    env = result.get("environment", {})
    if env.get("setting", "").lower().startswith("english"):
        score += 5
    if env.get("weather") == "0":
        score += 5
        
    return {
        "passed": score >= 60,
        "score": int(score),
        "feedback": " ".join(feedback)
    }