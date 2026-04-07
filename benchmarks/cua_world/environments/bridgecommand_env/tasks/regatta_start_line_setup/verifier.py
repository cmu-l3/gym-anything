#!/usr/bin/env python3
"""
Verifier for Regatta Start Line Configuration task.
Calculates geodesic geometry to verify the start line setup.
"""

import json
import math
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def calculate_bearing_distance(lat1, lon1, lat2, lon2):
    """
    Calculate bearing and distance (in nautical miles) between two points.
    Uses simple spherical approximation suitable for short distances (<1nm).
    """
    # Convert to radians
    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    # Diff in lat/lon in radians
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)

    # Average latitude for longitude scaling
    avg_lat = (lat1_rad + lat2_rad) / 2.0

    # Distance calculation (1 degree lat = 60 nm)
    # x = delta_lon_deg * 60 * cos(avg_lat)
    # y = delta_lat_deg * 60
    x = (lon2 - lon1) * 60.0 * math.cos(avg_lat)
    y = (lat2 - lat1) * 60.0
    
    dist_nm = math.sqrt(x*x + y*y)

    # Bearing calculation
    # atan2(x, y) returns angle from North (0 is North, 90 is East)
    # math.atan2(y, x) is standard cartesian
    # We want Compass bearing: 0=N, 90=E.
    # Compass bearing = atan2(x, y) converted to degrees
    bearing_rad = math.atan2(x, y)
    bearing_deg = math.degrees(bearing_rad)
    
    # Normalize to 0-360
    bearing_deg = (bearing_deg + 360) % 360

    return dist_nm, bearing_deg

def verify_regatta_start_line_setup(traj, env_info, task_info):
    """
    Verifies:
    1. Scenario files exist and structure is correct.
    2. Environment is Solent, Wind 235, Vis > 5.
    3. Ownship is at correct anchor position.
    4. Pin End Buoy is at correct relative bearing (Wind-90) and distance (0.25nm).
    5. Sailing yachts are present.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata targets
    meta = task_info.get('metadata', {})
    target_wind = meta.get('target_wind_dir', 235)
    target_dist = meta.get('target_line_dist_nm', 0.25)
    # Target bearing is Wind - 90 = 145 (normalized)
    target_bearing = (target_wind + meta.get('target_bearing_offset', -90) + 360) % 360
    
    tolerances = meta.get('tolerances', {})
    tol_bearing = tolerances.get('bearing_deg', 3.0)
    tol_dist_pct = tolerances.get('distance_pct', 10.0)
    tol_pos = tolerances.get('pos_deg', 0.001)

    # Load result
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

    # 1. Structure Check (10 pts)
    if result.get('scenario_exists') and result.get('files_created_during_task'):
        score += 10
        feedback.append("Scenario created correctly.")
    else:
        return {"passed": False, "score": 0, "feedback": "Scenario directory not created or files not new."}

    # 2. Environment Check (10 pts)
    env = result.get('environment', {})
    setting = env.get('Setting', '').lower()
    wind_dir = float(env.get('WindDirection', -1))
    
    if 'solent' in setting:
        score += 5
    else:
        feedback.append(f"Wrong setting: {setting}")

    if abs(wind_dir - target_wind) < 1.0:
        score += 5
    else:
        feedback.append(f"Wrong wind direction: {wind_dir} (expected {target_wind})")

    # 3. Ownship Check (10 pts)
    own = result.get('ownship', {})
    try:
        own_lat = float(own.get('InitialLat', -999))
        own_lon = float(own.get('InitialLong', -999))
        
        target_own_lat = meta.get('ownship_lat', 50.775)
        target_own_long = meta.get('ownship_long', -1.3)

        if (abs(own_lat - target_own_lat) < tol_pos and 
            abs(own_lon - target_own_long) < tol_pos):
            score += 10
        else:
            feedback.append(f"Committee boat pos incorrect: {own_lat},{own_lon}")
    except ValueError:
        feedback.append("Could not parse Ownship coordinates.")

    # 4. Geometry Check (Start Line) (50 pts)
    others = result.get('othership', [])
    pin_buoy_found = False
    
    if len(others) >= 1:
        # Assuming Vessel 1 is the Pin End as per task
        pin = others[0]
        try:
            pin_lat = float(pin.get('InitLat', -999))
            pin_lon = float(pin.get('InitLong', -999))
            
            # Calculate actual geometry
            act_dist, act_bearing = calculate_bearing_distance(
                own_lat, own_lon, pin_lat, pin_lon
            )
            
            # Verify Bearing (Orientation)
            bearing_diff = abs(act_bearing - target_bearing)
            if bearing_diff > 180: bearing_diff = 360 - bearing_diff
            
            if bearing_diff <= tol_bearing:
                score += 30
                feedback.append(f"Line orientation perfect ({act_bearing:.1f}°).")
            else:
                feedback.append(f"Line orientation wrong. Bearing: {act_bearing:.1f}° (Target: {target_bearing}°).")

            # Verify Distance (Length)
            dist_error_pct = abs(act_dist - target_dist) / target_dist * 100
            if dist_error_pct <= tol_dist_pct:
                score += 20
                feedback.append(f"Line length correct ({act_dist:.3f}nm).")
            else:
                feedback.append(f"Line length wrong: {act_dist:.3f}nm (Target: {target_dist}nm).")
                
            pin_buoy_found = True
        except ValueError:
            feedback.append("Could not parse Pin Buoy coordinates.")
    else:
        feedback.append("No Pin End buoy found.")

    # 5. Competitor Fleet Check (10 pts)
    # Check for at least 3 other vessels (total 4+) or just check types
    if len(others) >= 4:
        # Simple heuristic for sailing vessels
        sailing_count = 0
        for v in others:
            v_type = v.get('Type', '').lower()
            if 'yacht' in v_type or 'sail' in v_type:
                sailing_count += 1
        
        if sailing_count >= 3:
            score += 10
            feedback.append(f"Fleet fleet found ({sailing_count} sailing vessels).")
        else:
            feedback.append(f"Fleet models check failed (found {sailing_count} sailing vessels).")
    else:
        feedback.append(f"Not enough vessels created (found {len(others)}).")

    # 6. Documentation Check (10 pts)
    if result.get('docs_exists'):
        score += 10
    else:
        feedback.append("Coordinates text file missing.")

    passed = (score >= 70) and pin_buoy_found

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }