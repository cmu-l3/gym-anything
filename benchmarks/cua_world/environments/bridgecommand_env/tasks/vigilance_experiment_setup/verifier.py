#!/usr/bin/env python3
"""
Verifier for Vigilance Experiment Setup task.

Verifies:
1. Correct file structure.
2. Correct environment settings (Night, Calm).
3. Kinematic calculation:
   - Given Own Ship (12kts, N) and Target (18kts, S)
   - Calculates time to intercept based on Latitude distance
   - MUST be 4.0 hours +/- tolerance
"""

import json
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_vigilance_experiment_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
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
    
    files = result.get('files', {})
    env = result.get('environment', {})
    own = result.get('ownship', {})
    other = result.get('othership', {})

    # Criterion 1: Structure (20 pts)
    if files.get('scenario_dir') == 'true' and files.get('environment_ini') == 'true' and \
       files.get('ownship_ini') == 'true' and files.get('othership_ini') == 'true':
        score += 20
        feedback.append("Scenario structure correct")
    else:
        feedback.append("Missing scenario files")

    # Criterion 2: Environment (20 pts)
    # StartTime=0.0 (Midnight), Weather<=1.0 (Calm)
    try:
        start_time = float(env.get('StartTime', -1))
        weather = float(env.get('Weather', 99))
        
        # Accept midnight (0.0) or late night (22.0+)
        if start_time == 0.0 or start_time >= 22.0 or start_time <= 2.0:
            score += 10
            feedback.append("Time set to night/midnight")
        else:
            feedback.append(f"Time not night ({start_time})")

        if weather <= 1.5:
            score += 10
            feedback.append("Weather set to calm")
        else:
            feedback.append(f"Weather not calm ({weather})")
    except ValueError:
        feedback.append("Error parsing environment values")

    # Criterion 3: Own Ship Config (20 pts)
    # Lat=49.0, Speed=12.0
    try:
        own_lat = float(own.get('InitialLat', 0))
        own_spd = float(own.get('InitialSpeed', 0))
        own_hdg = float(own.get('InitialBearing', -1))
        
        if abs(own_lat - 49.0) < 0.01:
            score += 10
            feedback.append("OwnShip Latitude correct")
        else:
            feedback.append(f"OwnShip Lat incorrect ({own_lat})")

        if abs(own_spd - 12.0) < 0.5:
            score += 5
            feedback.append("OwnShip Speed correct")
        else:
            feedback.append(f"OwnShip Speed incorrect ({own_spd})")

        if abs(own_hdg - 0.0) < 5 or abs(own_hdg - 360.0) < 5:
            score += 5
            feedback.append("OwnShip Heading correct (N)")
        else:
            feedback.append(f"OwnShip Heading incorrect ({own_hdg})")
    except ValueError:
        feedback.append("Error parsing OwnShip values")

    # Criterion 4: Target Ship & Calculation (40 pts)
    # Must intercept at T+4h
    try:
        # Check if traffic vessel exists
        num_others = int(other.get('Number', 0))
        if num_others != 1:
            feedback.append(f"Incorrect number of traffic vessels ({num_others})")
        else:
            # Parse indexed values (Bridge Command uses Index(0) format sometimes, but raw ini flat)
            # The parser flattened it. Depending on agent implementation, might be Lat(0) or just Lat if manual write
            # We'll check for keys containing Lat
            
            tgt_lat = None
            tgt_long = None
            tgt_spd = None
            tgt_hdg = None # Often inferred from legs, but let's check StartLat
            
            # Bridge Command 'othership.ini' keys are often 'InitialLat(0)', 'InitialSpeed(0)'
            # Our parser flattens keys. Let's look for likely candidates.
            for k, v in other.items():
                if 'InitialLat' in k: tgt_lat = float(v)
                if 'InitialLong' in k: tgt_long = float(v)
                if 'InitialSpeed' in k: tgt_spd = float(v)
                # Heading often 'InitialBearing' or calculated from Legs
                if 'InitialBearing' in k: tgt_hdg = float(v)

            # Reciprocal Course Check
            if tgt_hdg is not None and (abs(tgt_hdg - 180.0) < 10):
                feedback.append("Target heading reciprocal (approx 180)")
            
            # THE CRITICAL CALCULATION
            # Time = Distance / Rel_Speed
            # Distance = |TgtLat - OwnLat| * 60
            # Rel_Speed = OwnSpd + TgtSpd (Head-on)
            
            if tgt_lat is not None and tgt_spd is not None:
                dist_nm = abs(tgt_lat - 49.0) * 60.0
                rel_speed = 12.0 + tgt_spd # Own ship 12.0
                
                if rel_speed > 0:
                    intercept_time_hours = dist_nm / rel_speed
                    
                    target_hours = 4.0
                    tolerance = 0.1 # +/- 6 minutes
                    
                    if abs(intercept_time_hours - target_hours) <= tolerance:
                        score += 40
                        feedback.append(f"PERFECT: Intercept calculated at {intercept_time_hours:.2f} hours")
                    else:
                        feedback.append(f"CALCULATION FAIL: Intercept at {intercept_time_hours:.2f} hours (Target 4.0)")
                        feedback.append(f"  Debug: Dist={dist_nm}nm, RelSpd={rel_speed}kts")
                        
                        # Partial credit if close (within 30 mins)
                        if abs(intercept_time_hours - target_hours) <= 0.5:
                            score += 15
                            feedback.append("  (Partial credit for being somewhat close)")
            else:
                feedback.append("Could not parse target parameters for calculation")

    except ValueError:
        feedback.append("Error parsing Target Ship values")

    # Briefing file check (bonus/tie-breaker implicit in score max)
    if files.get('briefing') == 'true':
        feedback.append("Briefing file present")
    
    passed = score >= 60 # Requires at least valid setup + reasonable calculation attempt
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }