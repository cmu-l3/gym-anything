#!/usr/bin/env python3
"""
Verifier for east_west_vertical_fin_shading task.

Checks:
1. Simulation ran during session (10 pts)
2. East windows have LEFT-FIN-H and RIGHT-FIN-H = 2.5 (40 pts)
3. West windows have LEFT-FIN-H and RIGHT-FIN-H = 2.5 (40 pts)
4. North/South windows do NOT have fins (10 pts)

Uses copy_from_env to retrieve the .inp file and parses it hierarchically.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Task-specific constants
TARGET_FIN_DEPTH = 2.5
TOLERANCE = 0.1
PROJECT_INP_PATH_CONTAINER = r"C:\Users\Docker\Documents\eQUEST 3-65 Projects\4StoreyBuilding\4StoreyBuilding.inp"
RESULT_JSON_PATH_CONTAINER = r"C:\workspace\tasks\east_west_vertical_fin_shading\task_result.json"

def parse_inp_file(content):
    """
    Parses eQUEST INP structure to find windows and their properties.
    Returns a list of window dictionaries with orientation context.
    
    Hierarchy: FLOOR -> SPACE -> EXTERIOR-WALL -> WINDOW
    """
    windows = []
    
    # State tracking
    current_floor = None
    current_space = None
    current_wall = None
    current_window = None
    
    # Regex patterns
    obj_pattern = re.compile(r'"([^"]+)"\s*=\s*([A-Z0-9-]+)')
    prop_pattern = re.compile(r'([A-Z0-9-]+)\s*=\s*([^=\r\n]+)')
    
    lines = content.split('\n')
    
    for line in lines:
        line = line.strip()
        
        # Check for object definition
        match = obj_pattern.match(line)
        if match:
            name, obj_type = match.groups()
            
            if obj_type == "FLOOR":
                current_floor = name
            elif obj_type == "SPACE":
                current_space = name
            elif obj_type == "EXTERIOR-WALL":
                current_wall = name
            elif obj_type == "WINDOW":
                current_window = {
                    "name": name,
                    "floor": current_floor,
                    "space": current_space,
                    "wall": current_wall,
                    "props": {}
                }
                windows.append(current_window)
            else:
                # Reset lower hierarchy if higher level changes, though INP is nested textually usually
                # strict nesting in INP is indicated by ".." but usually we can infer from structure
                pass
            continue
            
        # Check for property
        if current_window and "=" in line:
            # Simple property parser
            parts = line.split("=")
            if len(parts) >= 2:
                key = parts[0].strip()
                val = parts[1].strip().split('..')[0].strip() # Handle terminator
                current_window["props"][key] = val

    return windows

def get_zone_orientation(space_name):
    """Derive orientation from standard 4StoreyBuilding zone naming convention."""
    if not space_name:
        return "Unknown"
    # Naming convention: G.E02 -> Ground East, M.W24 -> Middle West
    # Look for .N, .S, .E, .W
    if ".E" in space_name:
        return "East"
    if ".W" in space_name:
        return "West"
    if ".N" in space_name:
        return "North"
    if ".S" in space_name:
        return "South"
    return "Core/Other"

def verify_east_west_vertical_fin_shading(traj, env_info, task_info):
    """
    Verify that vertical fins were applied correctly to East/West windows.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON (for simulation status)
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_JSON_PATH_CONTAINER, temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Could not retrieve task result (export script failed)."}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Retrieve INP File (for geometry check)
    inp_content = ""
    temp_inp = tempfile.NamedTemporaryFile(delete=False, suffix='.inp')
    try:
        copy_from_env(PROJECT_INP_PATH_CONTAINER, temp_inp.name)
        with open(temp_inp.name, 'r', encoding='latin-1') as f: # INP files are often legacy encoded
            inp_content = f.read()
    except Exception as e:
        logger.error(f"Failed to load INP file: {e}")
        return {"passed": False, "score": 0, "feedback": "Could not retrieve project file (.inp). Did you save the project?"}
    finally:
        if os.path.exists(temp_inp.name):
            os.unlink(temp_inp.name)

    # 3. Parse INP
    windows = parse_inp_file(inp_content)
    if not windows:
        return {"passed": False, "score": 0, "feedback": "Failed to parse building model data."}

    # 4. Evaluate Criteria
    score = 0
    feedback_parts = []
    
    # Criterion 1: Simulation Ran (10 pts)
    if task_result.get("sim_file_is_new", False):
        score += 10
        feedback_parts.append("Simulation run confirmed (+10).")
    else:
        feedback_parts.append("Simulation NOT run or old results found.")

    # Analyze Windows
    east_windows = []
    west_windows = []
    other_windows = []

    for w in windows:
        orientation = get_zone_orientation(w['space'])
        if orientation == "East":
            east_windows.append(w)
        elif orientation == "West":
            west_windows.append(w)
        elif orientation in ["North", "South"]:
            other_windows.append(w)

    # Criterion 2: East Windows (40 pts)
    east_pass_count = 0
    for w in east_windows:
        left = float(w['props'].get('LEFT-FIN-H', 0))
        right = float(w['props'].get('RIGHT-FIN-H', 0))
        if abs(left - TARGET_FIN_DEPTH) <= TOLERANCE and abs(right - TARGET_FIN_DEPTH) <= TOLERANCE:
            east_pass_count += 1
    
    east_score = 0
    if east_windows:
        east_score = int((east_pass_count / len(east_windows)) * 40)
    score += east_score
    feedback_parts.append(f"East Windows: {east_pass_count}/{len(east_windows)} correct (+{east_score}).")

    # Criterion 3: West Windows (40 pts)
    west_pass_count = 0
    for w in west_windows:
        left = float(w['props'].get('LEFT-FIN-H', 0))
        right = float(w['props'].get('RIGHT-FIN-H', 0))
        if abs(left - TARGET_FIN_DEPTH) <= TOLERANCE and abs(right - TARGET_FIN_DEPTH) <= TOLERANCE:
            west_pass_count += 1
            
    west_score = 0
    if west_windows:
        west_score = int((west_pass_count / len(west_windows)) * 40)
    score += west_score
    feedback_parts.append(f"West Windows: {west_pass_count}/{len(west_windows)} correct (+{west_score}).")

    # Criterion 4: North/South Penalty Check (10 pts)
    # Ensure they were NOT modified (fins should be 0 or missing)
    penalty_violations = 0
    for w in other_windows:
        left = float(w['props'].get('LEFT-FIN-H', 0))
        right = float(w['props'].get('RIGHT-FIN-H', 0))
        if left > 0.5 or right > 0.5: # Allow small tolerance for existing defaults if any, usually 0
            penalty_violations += 1
    
    penalty_score = 10
    if penalty_violations > 0:
        penalty_score = 0
        feedback_parts.append(f"Incorrectly added fins to {penalty_violations} North/South windows.")
    else:
        feedback_parts.append("North/South windows correctly left untouched (+10).")
    score += penalty_score

    # Final Check
    passed = (score >= 55) and task_result.get("sim_file_is_new", False) and (east_pass_count > 0 or west_pass_count > 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }