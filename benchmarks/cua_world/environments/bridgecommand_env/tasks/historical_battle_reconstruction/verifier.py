#!/usr/bin/env python3
"""
Verifier for Historical Battle Reconstruction task.

Verification Logic:
1. Validates the existence and structure of the scenario files.
2. Extracts coordinates of Ownship (Graf Spee) and Traffic (Exeter, Ajax, Achilles).
3. Calculates the geodetic Range and Bearing from Ownship to each Traffic vessel.
4. Compares calculated geometry against historical truth (metadata).
"""

import json
import math
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def calculate_rhumb_line(lat1, lon1, lat2, lon2):
    """
    Calculate rhumb line distance (nm) and bearing (degrees) between two points.
    Simple flat-earth approximation is sufficient for short ranges (<20nm).
    1 minute of latitude = 1 nautical mile.
    """
    # Convert inputs to float
    try:
        lat1, lon1 = float(lat1), float(lon1)
        lat2, lon2 = float(lat2), float(lon2)
    except (ValueError, TypeError):
        return None, None

    # Difference in latitude (minutes = nm)
    d_lat = (lat2 - lat1) * 60.0
    
    # Difference in longitude (minutes)
    d_lon = (lon2 - lon1) * 60.0
    
    # Departure (east-west distance in nm)
    # Scale d_lon by cosine of average latitude
    avg_lat_rad = math.radians((lat1 + lat2) / 2.0)
    departure = d_lon * math.cos(avg_lat_rad)
    
    # Distance
    distance = math.sqrt(d_lat**2 + departure**2)
    
    # Bearing (0-360)
    bearing_rad = math.atan2(departure, d_lat)
    bearing_deg = math.degrees(bearing_rad)
    
    if bearing_deg < 0:
        bearing_deg += 360.0
        
    return distance, bearing_deg

def verify_historical_battle_reconstruction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    ref_data = metadata.get('reference_data', {})
    tolerances = metadata.get('tolerances', {'range_nm': 0.5, 'bearing_deg': 5.0})

    # Load result from container
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
    feedback = []
    
    # Criterion 1: Scenario Structure (10 pts)
    if result.get('scenario_exists') and \
       result['files']['environment'] and \
       result['files']['ownship'] and \
       result['files']['othership']:
        score += 10
        feedback.append("Scenario files created successfully.")
    else:
        feedback.append("Missing scenario files.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Parse Ownship (Graf Spee) Position
    own_data = result['data'].get('ownship', {})
    try:
        own_lat = float(own_data.get('initiallat', -999))
        own_long = float(own_data.get('initiallong', -999))
        
        # Verify Ownship Position (10 pts)
        expected_lat = ref_data['spee']['lat']
        expected_long = ref_data['spee']['long']
        
        if abs(own_lat - expected_lat) < 0.05 and abs(own_long - expected_long) < 0.05:
            score += 10
            feedback.append("Graf Spee positioned correctly.")
        else:
            feedback.append(f"Graf Spee position error. Got ({own_lat}, {own_long}), expected ({expected_lat}, {expected_long}).")
            
    except (ValueError, TypeError):
        feedback.append("Invalid ownship coordinates.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # Analyze Traffic Vessels
    otherships = result['data'].get('othership', [])
    if len(otherships) < 3:
        feedback.append(f"Found {len(otherships)} traffic vessels, expected 3.")
    
    # We need to match vessels to targets based on relative position, 
    # since we don't know which index the agent assigned to which ship.
    targets_found = {
        'exeter': False,
        'ajax': False,
        'achilles': False
    }
    
    # Helper to check a vessel against a target
    def check_vessel_match(v_lat, v_lon, target_name):
        target_spec = ref_data[target_name]
        dist, brg = calculate_rhumb_line(own_lat, own_long, v_lat, v_lon)
        
        if dist is None: return False, 0, 0
        
        range_err = abs(dist - target_spec['range'])
        bearing_err = abs(brg - target_spec['bearing'])
        
        # Handle wrap-around for bearing error
        if bearing_err > 180:
            bearing_err = 360 - bearing_err
            
        match = (range_err <= tolerances['range_nm']) and (bearing_err <= tolerances['bearing_deg'])
        return match, range_err, bearing_err

    # Check each vessel in the scenario
    for i, vessel in enumerate(otherships):
        try:
            v_lat = float(vessel.get('initlat', 0))
            v_lon = float(vessel.get('initlong', 0))
            
            # Try to match against remaining targets
            matched_this_vessel = False
            
            for target in ['exeter', 'ajax', 'achilles']:
                if targets_found[target]: continue # Already found this one
                
                is_match, r_err, b_err = check_vessel_match(v_lat, v_lon, target)
                
                if is_match:
                    targets_found[target] = True
                    matched_this_vessel = True
                    # Scoring: 25 pts for Exeter, 25 for Ajax, 20 for Achilles
                    pts = 25 if target != 'achilles' else 20
                    score += pts
                    feedback.append(f"Matched {target.title()} (Err: R {r_err:.2f}nm, B {b_err:.1f}°)")
                    break
            
            if not matched_this_vessel:
                feedback.append(f"Vessel {i} did not match any historical target geometry.")
                
        except (ValueError, TypeError):
            feedback.append(f"Invalid coordinates for vessel {i}")

    # Criterion: Calculation File (10 pts)
    if result.get('calc_file_exists') and result.get('calc_file_fresh'):
        score += 10
        feedback.append("Calculation documentation created.")
    else:
        feedback.append("Calculation documentation missing or stale.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }