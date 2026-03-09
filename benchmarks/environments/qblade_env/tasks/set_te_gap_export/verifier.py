#!/usr/bin/env python3
"""
Verifier for set_te_gap_export@1

Checks that the agent correctly:
1. Created a NACA 4415 airfoil with a 2% trailing edge gap
2. Exported it to the specified .dat file path
3. The airfoil geometry is plausible
"""

import os
import sys
import json
import tempfile
import re
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_airfoil_dat(filepath):
    """Parse a standard .dat airfoil coordinate file."""
    result = {
        'header': '',
        'coords': [],
        'num_points': 0,
        'has_header': False,
        'parse_error': None
    }
    
    try:
        with open(filepath, 'r') as f:
            lines = f.readlines()
    except Exception as e:
        result['parse_error'] = f"Cannot read file: {e}"
        return result
    
    if not lines:
        result['parse_error'] = "File is empty"
        return result
    
    coords = []
    header_lines = []
    
    for line in lines:
        line = line.strip()
        if not line:
            continue
        
        # Try to parse as coordinate pair
        parts = re.split(r'[\s,;]+', line)
        try:
            if len(parts) >= 2:
                x = float(parts[0])
                y = float(parts[1])
                # Basic sanity check for normalized coordinates
                if -0.5 <= x <= 1.5 and -0.5 <= y <= 0.5:
                    coords.append((x, y))
                else:
                    if len(coords) == 0:
                        header_lines.append(line)
            else:
                if len(coords) == 0:
                    header_lines.append(line)
        except ValueError:
            if len(coords) == 0:
                header_lines.append(line)
    
    result['header'] = ' | '.join(header_lines[:3])
    result['has_header'] = len(header_lines) > 0
    result['coords'] = coords
    result['num_points'] = len(coords)
    
    return result

def find_trailing_edge_gap(coords):
    """Calculate trailing edge gap from coordinates."""
    if len(coords) < 10:
        return 0.0, False

    # Strategy: Find points closest to x=1.0
    # Usually the file starts at TE (upper), goes to LE, then to TE (lower)
    # Or starts at LE.
    
    # Sort by x descending to find points near 1.0
    # But we need to distinguish upper vs lower surface.
    
    # Simple heuristic: Find the two points with largest x values that are distinct
    # (distance > 0). If it's a closed sharp TE, they might be the same point (1.0, 0.0).
    
    # Better: Split into upper/lower based on min_x (Leading Edge)
    min_x_idx = 0
    min_x_val = coords[0][0]
    for i, (x, y) in enumerate(coords):
        if x < min_x_val:
            min_x_val = x
            min_x_idx = i
            
    upper = coords[:min_x_idx+1] # TE to LE
    lower = coords[min_x_idx:]   # LE to TE
    
    if not upper or not lower:
        return 0.0, False
        
    # Get endpoints (TE candidates)
    # Upper start or end?
    if abs(upper[0][0] - 1.0) < abs(upper[-1][0] - 1.0):
        te_upper = upper[0]
    else:
        te_upper = upper[-1] # Unlikely if format is standard
        
    if abs(lower[-1][0] - 1.0) < abs(lower[0][0] - 1.0):
        te_lower = lower[-1]
    else:
        te_lower = lower[0]
        
    # Check if they are actually near the trailing edge (x ~ 1.0)
    if te_upper[0] < 0.9 or te_lower[0] < 0.9:
        return 0.0, False
        
    gap = abs(te_upper[1] - te_lower[1])
    return gap, True

def analyze_geometry(coords):
    """Analyze thickness and camber."""
    if not coords:
        return 0, 0
    
    ys = [c[1] for c in coords]
    max_y = max(ys)
    min_y = min(ys)
    thickness = max_y - min_y
    
    return thickness

def verify_set_te_gap_export(traj, env_info, task_info):
    """Verify the set_te_gap_export task."""
    
    # 1. Setup and data retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/airfoils/naca4415_bluntTE.dat')
    target_gap = metadata.get('target_te_gap', 0.02)
    gap_tolerance = metadata.get('te_gap_tolerance', 0.008) # 1.2% to 2.8%
    
    # Copy result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # Copy the actual airfoil file for analysis
    temp_dat = tempfile.NamedTemporaryFile(delete=False, suffix='.dat')
    file_copied = False
    try:
        if result.get('output_exists'):
            copy_from_env(expected_path, temp_dat.name)
            file_copied = True
    except Exception as e:
        logger.warning(f"Could not copy dat file: {e}")
    
    score = 0
    feedback_parts = []
    
    # 2. Verify File Existence & Creation (25 points)
    if result.get('output_exists'):
        score += 15
        feedback_parts.append("Output file exists")
        
        if result.get('file_created_during_task'):
            score += 10
            feedback_parts.append("File created during task")
        else:
            feedback_parts.append("File timestamp predates task (potential pre-existing file)")
    else:
        feedback_parts.append("Output file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    # 3. Verify File Content & Geometry (75 points)
    if file_copied:
        parsed = parse_airfoil_dat(temp_dat.name)
        os.unlink(temp_dat.name)
        
        # Valid format check (15 pts)
        if parsed['num_points'] >= metadata.get('min_points', 30):
            score += 15
            feedback_parts.append(f"Valid coordinate data ({parsed['num_points']} points)")
            
            # Trailing Edge Gap Analysis (40 pts)
            gap, found_te = find_trailing_edge_gap(parsed['coords'])
            
            if found_te:
                # Check for NON-ZERO gap (bluntness applied)
                if gap > 0.002: # Minimal threshold
                    score += 15
                    feedback_parts.append("Blunt trailing edge detected")
                    
                    # Check for CORRECT gap (2% target)
                    if abs(gap - target_gap) <= gap_tolerance:
                        score += 25
                        feedback_parts.append(f"TE Gap correct ({gap:.4f}, target {target_gap})")
                    else:
                        feedback_parts.append(f"TE Gap incorrect ({gap:.4f}, target {target_gap})")
                else:
                    feedback_parts.append(f"Trailing edge is sharp (gap={gap:.4f}), modification not applied")
            else:
                feedback_parts.append("Could not identify trailing edge geometry")
                
            # Airfoil Shape/Thickness Check (20 pts)
            thickness = analyze_geometry(parsed['coords'])
            target_thick = metadata.get('target_thickness', 0.15)
            thick_tol = metadata.get('thickness_tolerance', 0.02)
            
            # Thickness is roughly max_y - min_y. For cambered 4415, thickness is 15%.
            # Coordinate max-min is a good proxy for thickness.
            if abs(thickness - target_thick) <= thick_tol:
                score += 20
                feedback_parts.append(f"Airfoil thickness correct (~{thickness:.3f})")
            else:
                feedback_parts.append(f"Airfoil thickness incorrect ({thickness:.3f}, expected ~{target_thick})")
                
        else:
            feedback_parts.append("File contains insufficient data points")
    else:
        feedback_parts.append("Could not analyze file content")

    # Pass logic: Need valid file, blunt TE detected, and reasonable thickness
    # Strict score threshold
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }