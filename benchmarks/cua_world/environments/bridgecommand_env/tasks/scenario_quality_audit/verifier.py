#!/usr/bin/env python3
"""
Verifier for scenario_quality_audit task.
Checks if 8 specific faults in Bridge Command INI files were corrected
and if a QA report was generated.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_scenario_quality_audit(traj, env_info, task_info):
    """
    Verify Scenario Quality Audit.
    
    Faults to check:
    1. environment.ini: StartTime (was 25.5) -> Should be 0-24
    2. environment.ini: StartMonth (was 15) -> Should be 1-12
    3. environment.ini: Weather (was 200.0) -> Should be 0-12
    4. ownship.ini: Coords (was Boston) -> Should be Humber (53.X)
    5. ownship.ini: Speed (was 85.0) -> Should be reasonable (<25)
    6. othership.ini: V2 Collision (was same as V1) -> Should be separated
    7. othership.ini: V2 Legs (was 0) -> Should be > 0
    8. othership.ini: V3 Speed (was 45.0) -> Should be reasonable (<20 for VLCC)
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
    
    files = result.get("files", {})
    report = result.get("report", {})
    
    # --- CHECK 1: ENVIRONMENT.INI (21 points) ---
    env = files.get("environment", {})
    
    # Fault 1: StartTime (7 pts)
    try:
        st = float(env.get("start_time", 25.5))
        if 0.0 <= st <= 24.0 and st != 25.5:
            score += 7
            feedback_parts.append("StartTime corrected")
        else:
            feedback_parts.append(f"StartTime invalid ({st})")
    except ValueError:
        feedback_parts.append("StartTime not a number")

    # Fault 2: StartMonth (7 pts)
    try:
        sm = int(env.get("start_month", 15))
        if 1 <= sm <= 12 and sm != 15:
            score += 7
            feedback_parts.append("StartMonth corrected")
        else:
            feedback_parts.append(f"StartMonth invalid ({sm})")
    except ValueError:
        feedback_parts.append("StartMonth not a number")

    # Fault 3: Weather (7 pts)
    try:
        w = float(env.get("weather", 200.0))
        if 0.0 <= w <= 12.0 and w != 200.0:
            score += 7
            feedback_parts.append("Weather corrected")
        else:
            feedback_parts.append(f"Weather invalid ({w})")
    except ValueError:
        feedback_parts.append("Weather not a number")

    # --- CHECK 2: OWNSHIP.INI (17 points) ---
    own = files.get("ownship", {})

    # Fault 4: Coordinates (10 pts) - Target Humber (Lat ~53.6)
    try:
        lat = float(own.get("lat", 0))
        # Humber is approx 53.5 - 53.7. Boston is 42.
        if 53.0 <= lat <= 54.0:
            score += 10
            feedback_parts.append("Coordinates corrected to Humber")
        else:
            feedback_parts.append(f"Coordinates wrong location ({lat})")
    except ValueError:
        feedback_parts.append("Lat not a number")

    # Fault 5: Speed (7 pts) - Target Cargo < 25kts
    try:
        spd = float(own.get("speed", 85.0))
        if 0 < spd <= 25.0 and spd != 85.0:
            score += 7
            feedback_parts.append("Ownship speed corrected")
        else:
            feedback_parts.append(f"Ownship speed unrealistic ({spd})")
    except ValueError:
        feedback_parts.append("Speed not a number")

    # --- CHECK 3: OTHERSHIP.INI (22 points) ---
    other = files.get("othership", {})

    # Fault 6: Collision (8 pts) - V2 should not equal V1 pos
    try:
        v1_lat = float(other.get("v1_lat", 0))
        v1_long = float(other.get("v1_long", 0))
        v2_lat = float(other.get("v2_lat", 0))
        v2_long = float(other.get("v2_long", 0))
        
        # Check delta
        lat_diff = abs(v1_lat - v2_lat)
        long_diff = abs(v1_long - v2_long)
        
        if lat_diff > 0.005 or long_diff > 0.005:
            score += 8
            feedback_parts.append("Vessel separation corrected")
        else:
            feedback_parts.append("Vessel 2 still colliding with Vessel 1")
    except ValueError:
        feedback_parts.append("Vessel positions invalid")

    # Fault 7: Legs (7 pts) - V2 legs > 0
    try:
        legs = int(other.get("v2_legs", 0))
        if legs > 0:
            score += 7
            feedback_parts.append("Vessel 2 waypoints added")
        else:
            feedback_parts.append("Vessel 2 still has 0 legs")
    except ValueError:
        feedback_parts.append("Legs invalid")

    # Fault 8: VLCC Speed (7 pts) - V3 speed < 20
    try:
        v3_spd = float(other.get("v3_speed", 45.0))
        if 0 < v3_spd <= 20.0 and v3_spd != 45.0:
            score += 7
            feedback_parts.append("VLCC speed corrected")
        else:
            feedback_parts.append(f"VLCC speed unrealistic ({v3_spd})")
    except ValueError:
        feedback_parts.append("VLCC speed invalid")

    # --- CHECK 4: REPORT (40 points) ---
    rep_exists = report.get("exists", False)
    rep_content = report.get("content", "").lower()
    
    if rep_exists and len(rep_content) > 50:
        score += 5  # Exists and non-empty
        
        # Check for keywords related to the faults
        keywords = {
            "time": 4, 
            "weather": 4, 
            "latitude": 4, 
            "speed": 5, 
            "collision": 5, 
            "waypoint": 5, 
            "legs": 4, 
            "ini": 4
        }
        
        kw_hits = 0
        kw_score = 0
        for kw, pts in keywords.items():
            if kw in rep_content:
                kw_hits += 1
                kw_score += pts
        
        # Cap keyword score at 35 (Total report = 5 + 35 = 40)
        score += min(35, kw_score)
        
        if kw_hits > 0:
            feedback_parts.append(f"Report found with {kw_hits} relevant terms")
        else:
            feedback_parts.append("Report found but missing technical keywords")
    else:
        feedback_parts.append("Report missing or too short")

    # --- FINAL SCORE ---
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }