#!/usr/bin/env python3
"""
Verifier for Hydrographic Survey Planning Task.

Validates:
1. Scenario structure and file existence.
2. Correct world setting.
3. Survey Vessel geometry:
   - Starting position matches Datum.
   - Waypoints form a parallel track pattern (Lawnmower).
   - Line lengths and spacing match mission specs.

Geometry Calculation:
Since Bridge Command uses spherical coordinates, we check distances using Haversine
and bearings using rhumb line or great circle logic. Given the short distances (<2nm),
planar approximation or simple spherical trig is sufficient.
"""

import json
import math
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def haversine_nm(lat1, lon1, lat2, lon2):
    """Calculate distance in nautical miles between two lat/lon points."""
    R = 3440.065 # Radius of Earth in nm
    
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    
    a = math.sin(dphi/2)**2 + math.cos(phi1)*math.cos(phi2)*math.sin(dlambda/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    
    return R * c

def bearing_deg(lat1, lon1, lat2, lon2):
    """Calculate initial bearing in degrees from point 1 to point 2."""
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dlambda = math.radians(lon2 - lon1)
    
    y = math.sin(dlambda) * math.cos(phi2)
    x = math.cos(phi1)*math.sin(phi2) - math.sin(phi1)*math.cos(phi2)*math.cos(dlambda)
    theta = math.atan2(y, x)
    
    return (math.degrees(theta) + 360) % 360

def verify_hydrographic_survey(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/hydro_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Structure Check (20 pts)
    if result.get('scenario_created') and result.get('env_file_exists') and result.get('other_file_exists'):
        score += 20
        feedback.append("Scenario files created.")
    else:
        feedback.append("Missing scenario files.")
        return {"passed": False, "score": 0, "feedback": "Scenario structure incomplete."}

    # 2. Created during task (Anti-gaming)
    if not result.get('created_during_task'):
        return {"passed": False, "score": 0, "feedback": "Scenario files were not modified during the task."}

    # Load specs (Truth)
    truth = result.get('truth_data', {})
    expected_lines = truth.get('lines', 6)
    expected_length = truth.get('length', 1.0)
    expected_spacing = truth.get('spacing', 0.1)
    expected_orient = truth.get('orientation', 90)
    
    # 3. World Setting (10 pts)
    actual_world = result.get('world_setting', '').strip().lower()
    expected_world = truth.get('world', '').strip().lower()
    if expected_world in actual_world:
        score += 10
        feedback.append("World setting correct.")
    else:
        feedback.append(f"World setting mismatch (Got {actual_world}, Expected {expected_world}).")

    # 4. Vessel Geometry Analysis
    vessel_data = result.get('vessel_data', {})
    if not vessel_data or "1" not in vessel_data:
        return {"passed": False, "score": score, "feedback": "No vessel data found in othership.ini"}
    
    vessel = vessel_data["1"]
    
    # Start Position Check (10 pts)
    start_lat = vessel.get('start_lat')
    start_long = vessel.get('start_long')
    
    if start_lat is not None and start_long is not None:
        dist_start = haversine_nm(start_lat, start_long, truth['datum_lat'], truth['datum_long'])
        if dist_start < 0.01: # 0.01 nm tolerance (~18m)
            score += 10
            feedback.append("Start position correct.")
        else:
            feedback.append(f"Start position off by {dist_start:.3f} nm.")
    else:
        feedback.append("Start position missing.")

    # Leg Analysis
    legs = vessel.get('legs', [])
    actual_leg_count = len(legs)
    
    # We expect: Line 1, Cross, Line 2, Cross, Line 3, Cross, Line 4, Cross, Line 5, Cross, Line 6
    # Total segments = 6 lines + 5 cross-legs = 11 segments
    # Bridge Command 'Legs' usually are waypoints AFTER the start.
    # So Leg 1 is end of Line 1. Leg 2 is end of Cross...
    
    expected_segments = (expected_lines * 2) - 1
    
    # Check Leg Count (20 pts)
    if actual_leg_count >= expected_lines: # lenient, at least the main lines
        score += 10
        if actual_leg_count >= expected_segments:
            score += 10
            feedback.append("Leg count correct.")
        else:
            feedback.append(f"Leg count low ({actual_leg_count}), expected {expected_segments}.")
    else:
        feedback.append(f"Insufficient legs ({actual_leg_count}).")

    # Geometry Check (40 pts)
    # We reconstruct the path: Start -> Leg1 -> Leg2 ...
    current_lat = start_lat
    current_long = start_long
    
    lines_ok = 0
    spacings_ok = 0
    
    # Tolerances
    len_tol = 0.15 # nm (15% of 1.0nm)
    bear_tol = 5.0 # degrees
    
    for i, leg in enumerate(legs):
        if i >= expected_segments: break
        
        next_lat = leg.get('lat')
        next_long = leg.get('long')
        
        if next_lat is None or next_long is None:
            continue
            
        dist = haversine_nm(current_lat, current_long, next_lat, next_long)
        bearing = bearing_deg(current_lat, current_long, next_lat, next_long)
        
        # Determine if this is a Survey Line (Indices 0, 2, 4...) or Cross Leg (1, 3, 5...)
        is_survey_line = (i % 2 == 0)
        
        if is_survey_line:
            # Check length
            if abs(dist - expected_length) < len_tol:
                # Check bearing (Alternating)
                # Line 0: Orientation
                # Line 2: Orientation + 180
                line_idx = i // 2
                target_bear = (expected_orient if line_idx % 2 == 0 else (expected_orient + 180) % 360)
                
                diff = abs(bearing - target_bear)
                diff = min(diff, 360 - diff)
                
                if diff < bear_tol:
                    lines_ok += 1
                else:
                    feedback.append(f"Leg {i+1} bearing off: {bearing:.1f} vs {target_bear:.1f}")
            else:
                 feedback.append(f"Leg {i+1} length off: {dist:.2f} vs {expected_length:.2f}")
        else:
            # Check spacing
            if abs(dist - expected_spacing) < (expected_spacing * 0.5): # Generous tolerance for short spacing
                spacings_ok += 1
                
        current_lat = next_lat
        current_long = next_long
        
    # Scoring Geometry
    # 30 pts for Lines
    line_score = min(30, int(30 * (lines_ok / expected_lines)))
    score += line_score
    
    # 10 pts for Spacing
    expected_cross = expected_lines - 1
    if expected_cross > 0:
        space_score = min(10, int(10 * (spacings_ok / expected_cross)))
        score += space_score
    
    feedback.append(f"Geometry: {lines_ok}/{expected_lines} lines good, {spacings_ok}/{expected_cross} cross-legs good.")
    
    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }