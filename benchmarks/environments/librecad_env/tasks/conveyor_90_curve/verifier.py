#!/usr/bin/env python3
"""
Verifier for conveyor_90_curve task.
Analyzes the DXF geometry extracted by the in-container script.
"""

import json
import os
import tempfile
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_conveyor_90_curve(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected metadata
    metadata = task_info.get('metadata', {})
    
    # 1. Fetch Result JSON
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
    
    # --- Criterion 1: File Submission (10 pts) ---
    if not result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "No output file found."}
    
    if not result.get('file_created_during_task', False):
        feedback.append("Warning: File timestamp indicates it wasn't modified during task.")
        # We don't fail immediately but penalize if strictly enforcing
    else:
        score += 10
        feedback.append("File created/modified successfully.")

    analysis = result.get('dxf_analysis', {})
    if not analysis.get('valid_dxf', False):
        return {"passed": False, "score": score, "feedback": "Output is not a valid DXF file."}

    # --- Criterion 2: Layers & Colors (15 pts) ---
    layers = analysis.get('layers', {})
    layer_score = 0
    
    # Check RAILS (Blue/5)
    if 'RAILS' in layers:
        layer_score += 2.5
        if layers['RAILS']['color'] == 5:
            layer_score += 2.5
    
    # Check ROLLERS (Yellow/2)
    if 'ROLLERS' in layers:
        layer_score += 2.5
        if layers['ROLLERS']['color'] == 2:
            layer_score += 2.5
            
    # Check NOTES (White/7)
    if 'NOTES' in layers:
        layer_score += 2.5
        if layers['NOTES']['color'] == 7:
            layer_score += 2.5
            
    score += layer_score
    feedback.append(f"Layers check: +{layer_score} pts")

    # --- Criterion 3: Rail Arcs (25 pts) ---
    arcs = analysis.get('arcs', [])
    rails_arcs = [a for a in arcs if a['layer'] == 'RAILS']
    
    r1000_found = False
    r1800_found = False
    angle_correct = False
    
    for arc in rails_arcs:
        r = arc['radius']
        # Check Center
        cx, cy = arc['center'][0], arc['center'][1]
        is_centered = abs(cx) < 1.0 and abs(cy) < 1.0
        
        if not is_centered:
            continue
            
        # Check Radius
        if abs(r - 1000) < 50:
            r1000_found = True
        elif abs(r - 1800) < 50:
            r1800_found = True
            
        # Check Angles (approx 0 to 90)
        # ezdxf angles are in degrees
        span = abs(arc['end_angle'] - arc['start_angle'])
        if span > 270: # handle crossing 0/360
             span = 360 - span
        
        if abs(span - 90) < 5:
            angle_correct = True

    if r1000_found and r1800_found:
        score += 15
        feedback.append("Found inner and outer rail arcs.")
    else:
        feedback.append(f"Missing rail arcs (Found R1000: {r1000_found}, R1800: {r1800_found}).")
        
    if angle_correct:
        score += 10
        feedback.append("Arc angles cover 90 degrees.")

    # --- Criterion 4: Roller Geometry (35 pts) ---
    lines = analysis.get('lines', [])
    rollers = [l for l in lines if l['layer'] == 'ROLLERS']
    
    expected_angles = [0, 15, 30, 45, 60, 75, 90]
    matched_angles = 0
    
    for target in expected_angles:
        found_match = False
        for roller in rollers:
            # Check length (1800-1000 = 800)
            if abs(roller['length'] - 800) > 100:
                continue
                
            # Check angle
            # Line angle could be target or target + 180 depending on draw direction
            a = roller['angle']
            diff = min(abs(a - target), abs(a - (target + 180)), abs(a - (target - 180)))
            
            if diff < 2.0:
                found_match = True
                break
        
        if found_match:
            matched_angles += 1
            
    # Score proportional to matched angles (5 pts per angle, max 35)
    roller_score = matched_angles * 5
    score += roller_score
    feedback.append(f"Rollers aligned at {matched_angles}/7 expected angles.")

    # --- Criterion 5: Precision/Connectivity (15 pts) ---
    # Check if roller endpoints lie on the radii
    precision_matches = 0
    for roller in rollers:
        d1 = math.sqrt(roller['start'][0]**2 + roller['start'][1]**2)
        d2 = math.sqrt(roller['end'][0]**2 + roller['end'][1]**2)
        
        # One end should be ~1000, other ~1800
        radii_match = (abs(d1 - 1000) < 20 and abs(d2 - 1800) < 20) or \
                      (abs(d1 - 1800) < 20 and abs(d2 - 1000) < 20)
                      
        if radii_match:
            precision_matches += 1
            
    # Score proportional to precision (approx 2 pts per roller)
    precision_score = min(15, precision_matches * 2.2)
    score += int(precision_score)
    feedback.append(f"Precision check: {precision_matches} rollers connected correctly.")

    passed = score >= 75 and r1000_found and r1800_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }