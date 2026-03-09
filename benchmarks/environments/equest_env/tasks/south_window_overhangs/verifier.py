#!/usr/bin/env python3
"""
Verifier for south_window_overhangs task.

Verifies:
1. Parse the 4StoreyBuilding.inp file.
2. Identify south-facing exterior walls (Azimuth approx 180).
3. Identify windows belonging to those walls.
4. Verify OVERHANG-D (3.0) and OVERHANG-A (0.5) on those windows.
5. Ensure no overhangs on non-south windows.
6. Check simulation ran.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants
TARGET_OVERHANG_D = 3.0
TARGET_OVERHANG_A = 0.5
TOLERANCE_D = 0.2
TOLERANCE_A = 0.1
TARGET_AZIMUTH = 180
AZIMUTH_TOLERANCE = 5.0

RESULT_JSON_PATH = "C:\\Users\\Docker\\south_window_overhangs_result.json"
INP_FILE_PATH = "C:\\Users\\Docker\\Documents\\eQUEST 3-65 Projects\\4StoreyBuilding\\4StoreyBuilding.inp"

def parse_inp_file(content):
    """
    Parses a DOE-2 INP/BDL file into a hierarchical structure.
    Returns a list of objects. Each object is a dict:
    {'name': str, 'type': str, 'props': dict, 'children': list}
    """
    objects = []
    stack = [] # Stack of parent objects
    
    # Regex for BDL objects: "Name" = TYPE
    # And properties: KEY = VALUE
    # And terminator: ..
    
    # Simple line-based parser (robust enough for standard eQUEST formatting)
    lines = content.splitlines()
    current_obj = None
    
    for line in lines:
        line = line.strip()
        # Remove comments
        if '$' in line:
            line = line.split('$')[0].strip()
        if not line:
            continue
            
        # Check for Object Start: "Name" = TYPE
        match_obj = re.match(r'^"([^"]+)"\s*=\s*([A-Z0-9-]+)', line, re.IGNORECASE)
        if match_obj:
            name = match_obj.group(1)
            obj_type = match_obj.group(2).upper()
            new_obj = {
                'name': name,
                'type': obj_type,
                'props': {},
                'children': []
            }
            
            if stack:
                stack[-1]['children'].append(new_obj)
            else:
                objects.append(new_obj)
                
            stack.append(new_obj)
            continue
            
        # Check for Property: KEY = VALUE
        match_prop = re.match(r'^([A-Z0-9-]+)\s*=\s*(.+)', line, re.IGNORECASE)
        if match_prop and stack:
            key = match_prop.group(1).upper()
            val = match_prop.group(2).rstrip(',') # Remove trailing comma if any
            
            # Try to convert to float
            try:
                val_num = float(val)
                stack[-1]['props'][key] = val_num
            except ValueError:
                stack[-1]['props'][key] = val.strip('"')
            continue
            
        # Check for Terminator: ..
        if line == '..' and stack:
            stack.pop()
            continue
            
    return objects

def find_south_windows(objects, parent_azimuth=0):
    """
    Recursively finds windows and determines their orientation based on parent walls.
    Returns list of {'window': obj_dict, 'azimuth': float}
    """
    windows = []
    
    for obj in objects:
        current_azimuth = parent_azimuth
        
        # Update azimuth if this object defines it (e.g., EXTERIOR-WALL)
        if 'AZIMUTH' in obj['props']:
            current_azimuth = obj['props']['AZIMUTH']
            
        if obj['type'] == 'WINDOW':
            windows.append({
                'window': obj,
                'azimuth': current_azimuth
            })
        
        # Recurse
        windows.extend(find_south_windows(obj['children'], current_azimuth))
        
    return windows

def verify_south_window_overhangs(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Get Result JSON
    result_data = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp_json:
        try:
            copy_from_env(RESULT_JSON_PATH, tmp_json.name)
            with open(tmp_json.name, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}
        finally:
            if os.path.exists(tmp_json.name):
                os.unlink(tmp_json.name)

    # 2. Get INP File
    inp_content = ""
    with tempfile.NamedTemporaryFile(delete=False, suffix='.inp') as tmp_inp:
        try:
            copy_from_env(INP_FILE_PATH, tmp_inp.name)
            with open(tmp_inp.name, 'r', errors='ignore') as f:
                inp_content = f.read()
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve INP file: {e}"}
        finally:
            if os.path.exists(tmp_inp.name):
                os.unlink(tmp_inp.name)

    # 3. Parse INP File
    try:
        model_objects = parse_inp_file(inp_content)
        all_windows = find_south_windows(model_objects)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error parsing INP file: {e}"}

    score = 0
    feedback_parts = []
    
    # Criteria Counters
    south_windows_total = 0
    south_windows_correct_depth = 0
    south_windows_correct_angle = 0
    non_south_spurious = 0
    
    # 4. Evaluate Windows
    for item in all_windows:
        win = item['window']
        azimuth = item['azimuth']
        props = win['props']
        name = win['name']
        
        # Check if South Facing (180 +/- 5)
        # Note: BDL Azimuths are typically 0=N, 90=E, 180=S, 270=W
        is_south = abs(azimuth - TARGET_AZIMUTH) <= AZIMUTH_TOLERANCE
        
        # Check properties
        depth = props.get('OVERHANG-D', 0)
        angle = props.get('OVERHANG-A', 0) # Distance above window
        
        if is_south:
            south_windows_total += 1
            
            # Verify Depth
            if abs(depth - TARGET_OVERHANG_D) <= TOLERANCE_D:
                south_windows_correct_depth += 1
            else:
                logger.info(f"Window {name} (South) has wrong depth: {depth}")
                
            # Verify Offset
            if abs(angle - TARGET_OVERHANG_A) <= TOLERANCE_A:
                south_windows_correct_angle += 1
            else:
                logger.info(f"Window {name} (South) has wrong offset: {angle}")
        
        else:
            # Verify no overhangs on non-south windows
            if depth > 0 or angle > 0:
                non_south_spurious += 1
                logger.info(f"Window {name} (Az={azimuth}) has spurious overhang: D={depth}, A={angle}")

    # 5. Calculate Score
    
    # 5.1 Simulation Run (10 pts)
    if result_data.get('sim_file_is_new', False):
        score += 10
        feedback_parts.append("Simulation ran successfully (+10)")
    else:
        feedback_parts.append("Simulation did not run")
        
    # 5.2 South Windows Depth (40 pts)
    if south_windows_total > 0:
        depth_score = (south_windows_correct_depth / south_windows_total) * 40
        score += depth_score
        if south_windows_correct_depth == south_windows_total:
            feedback_parts.append("All south window depths correct (+40)")
        elif south_windows_correct_depth > 0:
            feedback_parts.append(f"Partial south window depths correct ({int(depth_score)}/40)")
        else:
            feedback_parts.append("No south window depths correct")
    else:
        feedback_parts.append("Error: No south windows found in model")
        
    # 5.3 South Windows Offset (30 pts)
    if south_windows_total > 0:
        angle_score = (south_windows_correct_angle / south_windows_total) * 30
        score += angle_score
        if south_windows_correct_angle == south_windows_total:
            feedback_parts.append("All south window offsets correct (+30)")
        elif south_windows_correct_angle > 0:
            feedback_parts.append(f"Partial south window offsets correct ({int(angle_score)}/30)")
    
    # 5.4 Spurious Overhangs (20 pts)
    if non_south_spurious == 0:
        score += 20
        feedback_parts.append("No spurious overhangs (+20)")
    else:
        # Deduct points for spurious edits
        penalty = min(20, non_south_spurious * 2)
        score += (20 - penalty)
        feedback_parts.append(f"Found {non_south_spurious} spurious overhangs on non-south windows")

    passed = (score >= 60) and result_data.get('sim_file_is_new', False) and (south_windows_correct_depth >= south_windows_total * 0.8)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": ". ".join(feedback_parts)
    }