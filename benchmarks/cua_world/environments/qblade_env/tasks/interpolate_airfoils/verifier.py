#!/usr/bin/env python3
"""
Verifier for interpolate_airfoils task.

Verifies:
1. File existence and valid creation timestamp.
2. File content format (Selig airfoil format).
3. Geometric properties: Max thickness ~18% and Max camber ~3%.
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_interpolate_airfoils(traj, env_info, task_info):
    """
    Verify the interpolated airfoil task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Tolerances
    target_thick_min = metadata.get('target_thickness_min', 0.15)
    target_thick_max = metadata.get('target_thickness_max', 0.21)
    target_camber_min = metadata.get('target_camber_min', 0.02)
    target_camber_max = metadata.get('target_camber_max', 0.04)
    min_points = metadata.get('min_points', 30)

    # Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error loading result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # 1. Check file existence and timestamp (20 points)
    if not result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file not found"}
    
    score += 10
    feedback_parts.append("File exists")

    if result.get('file_created_during_task', False):
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp invalid (pre-dated)")
    
    # 2. Analyze Airfoil Geometry (80 points)
    # Copy the dat file out
    temp_dat = tempfile.NamedTemporaryFile(delete=False, suffix='.dat')
    try:
        copy_from_env("/tmp/interpolated_output.dat", temp_dat.name)
        with open(temp_dat.name, 'r') as f:
            lines = f.readlines()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Could not read output file: {e}"}
    finally:
        if os.path.exists(temp_dat.name):
            os.unlink(temp_dat.name)

    # Parse coordinates
    coords = []
    try:
        # Skip header (first line)
        for line in lines[1:]:
            parts = line.split()
            if len(parts) >= 2:
                try:
                    x = float(parts[0])
                    y = float(parts[1])
                    coords.append((x, y))
                except ValueError:
                    continue
    except Exception as e:
         return {"passed": False, "score": score, "feedback": f"Error parsing coordinates: {e}"}

    if len(coords) < min_points:
        return {"passed": False, "score": score, "feedback": f"File contains too few points ({len(coords)}), expected >{min_points}"}
    
    score += 10 # valid format points
    feedback_parts.append(f"Valid coordinate format ({len(coords)} points)")

    # Analyze thickness and camber
    try:
        max_thickness, max_camber = analyze_airfoil_geometry(coords)
        
        # Check Thickness (35 points)
        # Expected: ~0.18 (18%)
        if target_thick_min <= max_thickness <= target_thick_max:
            score += 35
            feedback_parts.append(f"Thickness {max_thickness:.1%} is within target range ({target_thick_min:.0%}-{target_thick_max:.0%})")
        else:
            feedback_parts.append(f"Thickness {max_thickness:.1%} OUT of range ({target_thick_min:.0%}-{target_thick_max:.0%})")
            
        # Check Camber (35 points)
        # Expected: ~0.03 (3%)
        if target_camber_min <= max_camber <= target_camber_max:
            score += 35
            feedback_parts.append(f"Camber {max_camber:.1%} is within target range ({target_camber_min:.0%}-{target_camber_max:.0%})")
        else:
            feedback_parts.append(f"Camber {max_camber:.1%} OUT of range ({target_camber_min:.0%}-{target_camber_max:.0%})")

    except Exception as e:
        feedback_parts.append(f"Geometry analysis failed: {str(e)}")

    passed = score >= 80  # Requires valid file + correct thickness + correct camber
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }

def analyze_airfoil_geometry(coords):
    """
    Estimate max thickness and camber from point list.
    Assumes Selig format: Trailing Edge -> Upper Surface -> Leading Edge -> Lower Surface -> Trailing Edge.
    """
    # 1. Find Leading Edge (min x)
    le_idx = 0
    min_x = 1.0
    for i, (x, y) in enumerate(coords):
        if x < min_x:
            min_x = x
            le_idx = i
            
    # Split into upper and lower
    # Note: In Selig format, points usually go 1.0 -> 0.0 (Upper) then 0.0 -> 1.0 (Lower)
    # OR 1.0 -> 0.0 (Lower) then 0.0 -> 1.0 (Upper)
    # We detect based on y values near x=0.5
    
    upper = []
    lower = []
    
    # Split list at LE
    part1 = coords[:le_idx+1] # 1.0 down to 0.0
    part2 = coords[le_idx:]   # 0.0 up to 1.0
    
    # Determine which part is upper (higher Y average)
    avg_y1 = sum(p[1] for p in part1)/len(part1) if part1 else 0
    avg_y2 = sum(p[1] for p in part2)/len(part2) if part2 else 0
    
    if avg_y1 > avg_y2:
        upper = part1
        lower = part2
    else:
        upper = part2
        lower = part1
        
    # Sort both by X for interpolation
    upper.sort(key=lambda p: p[0])
    lower.sort(key=lambda p: p[0])
    
    # Calculate Thickness and Camber distributions
    # We iterate through X from 0 to 1 with step 0.01
    max_t = 0.0
    max_c = 0.0
    
    steps = 100
    for i in range(steps):
        x_eval = i / float(steps)
        if x_eval < 0.01 or x_eval > 0.99: continue # Skip edges
        
        y_u = interpolate_y(upper, x_eval)
        y_l = interpolate_y(lower, x_eval)
        
        if y_u is not None and y_l is not None:
            thickness = y_u - y_l
            camber = (y_u + y_l) / 2.0
            
            if thickness > max_t: max_t = thickness
            if abs(camber) > max_c: max_c = abs(camber)
            
    return max_t, max_c

def interpolate_y(points, x_eval):
    """Linear interpolation of Y at X_eval given sorted points [(x,y)...]"""
    for i in range(len(points) - 1):
        x1, y1 = points[i]
        x2, y2 = points[i+1]
        
        if x1 <= x_eval <= x2 or x2 <= x_eval <= x1:
            if abs(x2 - x1) < 1e-6: return y1
            ratio = (x_eval - x1) / (x2 - x1)
            return y1 + ratio * (y2 - y1)
    return None