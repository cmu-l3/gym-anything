#!/usr/bin/env python3
import json
import math
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mmo_calibration(traj, env_info, task_info):
    """
    Verify the MMO Calibration Scenario.
    
    Calculates the geodetic distance and bearing between the user-placed ownship
    and user-placed targets to verify they match the requested relative geometry.
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    files = result.get('files_exist', {})
    if not files.get('scenario_dir') or not files.get('ownship'):
        return {"passed": False, "score": 0, "feedback": "Scenario files not found. Did you create the directory and INI files?"}

    ownship = result.get('ownship', {})
    targets = result.get('targets', [])
    env = result.get('environment', {})
    
    # 3. Helper Functions (Haversine)
    def to_rad(deg):
        return float(deg) * math.pi / 180.0

    def to_deg(rad):
        return float(rad) * 180.0 / math.pi

    def calculate_dist_bearing(lat1, lon1, lat2, lon2):
        """Returns distance in meters and true bearing in degrees"""
        R = 6371000 # Earth radius in meters
        
        phi1 = to_rad(lat1)
        phi2 = to_rad(lat2)
        dphi = to_rad(lat2 - lat1)
        dlambda = to_rad(lon2 - lon1)
        
        # Distance
        a = math.sin(dphi/2)**2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda/2)**2
        c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
        dist = R * c
        
        # Bearing
        y = math.sin(dlambda) * math.cos(phi2)
        x = math.cos(phi1) * math.sin(phi2) - math.sin(phi1) * math.cos(phi2) * math.cos(dlambda)
        brng = to_deg(math.atan2(y, x))
        brng = (brng + 360) % 360
        
        return dist, brng

    # 4. Scoring Criteria
    score = 0
    feedback = []

    # Criterion 1: Environment & Setup (20 pts)
    # Check Weather/Visibility
    vis = float(env.get('VisibilityRange', 0))
    weather = float(env.get('Weather', 99))
    
    if vis >= 10.0:
        score += 5
        feedback.append("Visibility OK")
    else:
        feedback.append(f"Visibility too low ({vis})")
        
    if weather <= 1.5:
        score += 5
        feedback.append("Weather OK")
    else:
        feedback.append(f"Weather too rough ({weather})")
        
    # Check Files
    if files.get('othership') and len(targets) == 4:
        score += 10
        feedback.append("Correct number of targets found")
    else:
        feedback.append(f"Expected 4 targets, found {len(targets)}")

    # Criterion 2: Ownship Placement (20 pts)
    try:
        own_lat = float(ownship.get('InitialLat', 0))
        own_long = float(ownship.get('InitialLong', 0))
        own_head = float(ownship.get('InitialBearing', 0))
        
        if abs(own_lat - 50.7000) < 0.001 and abs(own_long - (-1.3000)) < 0.001:
            score += 10
            feedback.append("Ownship position correct")
        else:
            feedback.append(f"Ownship position mismatch: {own_lat}, {own_long}")
            
        if abs(own_head - 90.0) < 2.0:
            score += 10
            feedback.append("Ownship heading correct")
        else:
            feedback.append(f"Ownship heading incorrect: {own_head}")
            
    except ValueError:
        return {"passed": False, "score": score, "feedback": "Could not parse Ownship coordinates"}

    # Criterion 3: Target Geometries (60 pts)
    # Expected: 
    # T1: 500m @ 90T (Dead Ahead)
    # T2: 500m @ 180T (Stbd Beam)
    # T3: 1000m @ 000T (Port Beam)
    # T4: 200m @ 270T (Astern)
    
    expected_targets = [
        {"desc": "Ahead", "dist": 500, "brng": 90},
        {"desc": "Stbd", "dist": 500, "brng": 180},
        {"desc": "Port", "dist": 1000, "brng": 0},
        {"desc": "Astern", "dist": 200, "brng": 270}
    ]
    
    # We try to match found targets to expected ones to allow flexible ordering
    matched_count = 0
    
    for exp in expected_targets:
        best_match = None
        min_error = float('inf')
        
        for t in targets:
            try:
                t_lat = float(t.get('lat', 0))
                t_long = float(t.get('long', 0))
                
                dist, brng = calculate_dist_bearing(own_lat, own_long, t_lat, t_long)
                
                # Check bearing error (handle 0/360 wrap)
                brng_err = min(abs(brng - exp['brng']), abs(brng - exp['brng'] + 360), abs(brng - exp['brng'] - 360))
                dist_err = abs(dist - exp['dist'])
                
                # Combined error metric for matching
                total_err = (dist_err / 100) + (brng_err / 10)
                
                if total_err < min_error:
                    min_error = total_err
                    best_match = {
                        "dist": dist,
                        "brng": brng,
                        "dist_err": dist_err,
                        "brng_err": brng_err
                    }
            except:
                continue
                
        # Evaluate Best Match
        if best_match:
            # Tolerances: 10% distance or 50m, 5 degrees bearing
            dist_ok = best_match['dist_err'] <= max(50, exp['dist'] * 0.1)
            brng_ok = best_match['brng_err'] <= 5.0
            
            if dist_ok and brng_ok:
                score += 15
                matched_count += 1
                feedback.append(f"Target {exp['desc']} OK (err: {best_match['dist_err']:.1f}m, {best_match['brng_err']:.1f}deg)")
            else:
                feedback.append(f"Target {exp['desc']} inaccurate. Found: {best_match['dist']:.1f}m @ {best_match['brng']:.1f}deg")
        else:
            feedback.append(f"Target {exp['desc']} not found")

    # Anti-gaming: Check if work done during task
    start_time = result.get('start_time', 0)
    file_mtime = result.get('file_mtime', 0)
    
    if file_mtime < start_time:
        feedback.append("WARNING: Files not modified during task session.")
        score = 0 # Fail if no work done

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }