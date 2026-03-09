#!/usr/bin/env python3
"""
Verifier for window_frame_thermal_bridging_update task.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_inp_windows(inp_content):
    """
    Parses eQUEST .inp content to extract window properties grouped by floor/space.
    
    Returns a list of dicts: 
    [
        {
            "name": "WindowName",
            "parent_space": "SpaceName",
            "frame_width": float or None,
            "frame_conduct": float or None
        }, ...
    ]
    """
    windows = []
    
    # BDL structure is hierarchical, but objects are often flattened in the INP 
    # with references to parents.
    # Typical structure:
    # "SpaceName" = SPACE ...
    # "WallName" = EXTERIOR-WALL ...
    # "WindowName" = WINDOW
    #    FRAME-WIDTH = X
    #    FRAME-CONDUCT = Y
    #    ...
    # ..
    # ..
    
    # We need to track the current parent space.
    current_space = None
    
    # Regex patterns
    space_pattern = re.compile(r'"([^"]+)"\s*=\s*SPACE')
    window_start_pattern = re.compile(r'"([^"]+)"\s*=\s*WINDOW')
    end_pattern = re.compile(r'\s*\.\.$') # Ends an object
    
    param_pattern = re.compile(r'([A-Z0-9-]+)\s*=\s*([^=\s]+)')
    
    lines = inp_content.splitlines()
    
    # Simple state machine
    current_object_type = None
    current_window_data = {}
    
    for line in lines:
        line = line.strip()
        # Remove comments
        if '$' in line:
            line = line.split('$')[0].strip()
        if not line:
            continue
            
        # Check for SPACE start
        m_space = space_pattern.match(line)
        if m_space:
            current_space = m_space.group(1)
            current_object_type = "SPACE"
            continue
            
        # Check for WINDOW start
        m_win = window_start_pattern.match(line)
        if m_win:
            current_object_type = "WINDOW"
            current_window_data = {
                "name": m_win.group(1),
                "parent_space": current_space,
                "frame_width": None,
                "frame_conduct": None
            }
            continue
            
        # Check for object end
        if end_pattern.match(line):
            if current_object_type == "WINDOW":
                windows.append(current_window_data)
            current_object_type = None
            continue
            
        # Extract parameters if inside WINDOW
        if current_object_type == "WINDOW":
            # Find all parameters in line
            params = param_pattern.findall(line)
            for key, val in params:
                if key == "FRAME-WIDTH":
                    try: current_window_data["frame_width"] = float(val)
                    except: pass
                elif key == "FRAME-CONDUCT":
                    try: current_window_data["frame_conduct"] = float(val)
                    except: pass
                    
    return windows

def verify_window_frame_thermal_bridging_update(traj, env_info, task_info):
    """
    Verifies the task:
    1. Simulation must have run (check result.json).
    2. Ground floor windows (space starts with "G.") must have updated frame props.
    3. Other windows must NOT be updated.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_width = metadata.get('target_frame_width', 0.21)
    target_conduct = metadata.get('target_frame_conductance', 2.2)
    
    # 1. Retrieve Result JSON
    result_data = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load result json: {e}")
    finally:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)
        
    # 2. Retrieve INP File
    inp_content = ""
    temp_inp = tempfile.NamedTemporaryFile(delete=False, suffix='.inp')
    inp_path = "C:\\Users\\Docker\\Documents\\eQUEST 3-65 Projects\\4StoreyBuilding\\4StoreyBuilding.inp"
    try:
        copy_from_env(inp_path, temp_inp.name)
        # INP files are usually ASCII/Latin-1
        with open(temp_inp.name, 'r', encoding='latin-1', errors='ignore') as f:
            inp_content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve project file (.inp): {e}"}
    finally:
        if os.path.exists(temp_inp.name): os.unlink(temp_inp.name)
        
    # Scoring
    score = 0
    feedback = []
    
    # Criterion 1: Simulation Run (10 pts)
    if result_data.get('sim_is_new', False):
        score += 10
        feedback.append("Simulation run confirmed.")
    else:
        feedback.append("Simulation NOT run (or output file not new).")
        
    # Criterion 2: Check Windows
    windows = parse_inp_windows(inp_content)
    if not windows:
        return {"passed": False, "score": 0, "feedback": "Could not parse windows from INP file."}
        
    gf_windows = [w for w in windows if w['parent_space'] and w['parent_space'].startswith("G.")]
    other_windows = [w for w in windows if w['parent_space'] and not w['parent_space'].startswith("G.")]
    
    # Check GF Windows (80 pts total)
    # Split into Width (40) and Conduct (40)
    width_ok_count = 0
    conduct_ok_count = 0
    
    for w in gf_windows:
        if w['frame_width'] is not None and abs(w['frame_width'] - target_width) < 0.001:
            width_ok_count += 1
        if w['frame_conduct'] is not None and abs(w['frame_conduct'] - target_conduct) < 0.1:
            conduct_ok_count += 1
            
    gf_total = len(gf_windows) if gf_windows else 1
    
    # Proportional scoring
    score_width = (width_ok_count / gf_total) * 40
    score_conduct = (conduct_ok_count / gf_total) * 40
    
    score += score_width
    score += score_conduct
    
    feedback.append(f"Ground Floor Windows: {width_ok_count}/{gf_total} correct width.")
    feedback.append(f"Ground Floor Windows: {conduct_ok_count}/{gf_total} correct conductance.")
    
    # Criterion 3: Precision (10 pts) - Ensure others not changed
    # Assume default width is 0 or None in the clean file. 
    # If agent did "Select All", these would match the target.
    errors_upper = 0
    for w in other_windows:
        # If matches target closely, it's likely a mistake (unless target is default, but 0.21/2.2 are specific)
        if w['frame_width'] is not None and abs(w['frame_width'] - target_width) < 0.001:
            errors_upper += 1
        elif w['frame_conduct'] is not None and abs(w['frame_conduct'] - target_conduct) < 0.1:
            errors_upper += 1
            
    if errors_upper == 0:
        score += 10
        feedback.append("Precision bonus: Upper floor windows untouched.")
    else:
        feedback.append(f"Precision penalty: {errors_upper} upper floor windows modified.")
        
    score = int(score)
    passed = (score >= 65) and result_data.get('sim_is_new', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }