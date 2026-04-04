#!/usr/bin/env python3
"""
Verifier for top_floor_custom_glazing_retrofit task.
Parses the eQUEST DOE-2 (.inp) file to verify:
1. A new Glass Type exists with U=0.24, SC=0.25.
2. Top Floor windows use this new glass type.
3. Lower Floor windows do NOT use this glass type.
4. Simulation was run.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants
TARGET_U = 0.24
TARGET_SC = 0.25
TOLERANCE = 0.01

def verify_top_floor_custom_glazing_retrofit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Retrieve Result JSON
    result_json_path = "C:\\Users\\Docker\\task_result.json"
    local_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    
    try:
        copy_from_env(result_json_path, local_json)
        with open(local_json, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(local_json):
            os.remove(local_json)

    # 2. Check Simulation Status (10 pts)
    score = 0
    feedback = []
    
    if result_data.get('sim_file_is_new'):
        score += 10
        feedback.append("Simulation run successfully (+10)")
    else:
        feedback.append("Simulation NOT run or saved (+0)")

    # 3. Retrieve and Parse INP File
    inp_path = result_data.get('inp_file_path', "C:\\Users\\Docker\\Documents\\eQUEST 3-65 Projects\\4StoreyBuilding\\4StoreyBuilding.inp")
    local_inp = tempfile.NamedTemporaryFile(delete=False, suffix='.inp').name
    
    try:
        copy_from_env(inp_path, local_inp)
        with open(local_inp, 'r', encoding='ISO-8859-1') as f:
            inp_content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to retrieve project file: {str(e)} | " + " | ".join(feedback)}
    finally:
        if os.path.exists(local_inp):
            os.remove(local_inp)

    # --- PARSING LOGIC ---
    
    # Step A: Find matching Glass Types
    # Format: "Name" = GLASS-TYPE ... GLASS-CONDUCT = X ... SHADING-COEF = Y ... ..
    glass_types = {} # name -> {u, sc}
    
    # Regex to capture glass type blocks
    # Note: DOE-2 files are line-based but commands span lines. We need a tokenizer or a state machine.
    # Simple state machine approach:
    
    lines = inp_content.splitlines()
    current_obj_type = None
    current_obj_name = None
    properties = {}
    
    valid_glass_names = [] # Names of glass types that match our criteria
    
    # Simplified parsing for Glass Types
    # We look for "NAME" = GLASS-TYPE and capture its properties until ".."
    
    glass_pattern = re.compile(r'"([^"]+)"\s*=\s*GLASS-TYPE')
    
    for i, line in enumerate(lines):
        line = line.split('$')[0].strip() # Remove comments
        if not line: continue
        
        # Start of definition
        m = glass_pattern.match(line)
        if m:
            current_obj_name = m.group(1)
            current_obj_type = "GLASS-TYPE"
            properties = {}
            continue
            
        if current_obj_type == "GLASS-TYPE":
            # Check for end of block
            if line.strip() == "..":
                # Check properties
                u_val = properties.get('GLASS-CONDUCT', 999.0)
                sc_val = properties.get('SHADING-COEF', 999.0)
                
                # Check match
                if abs(u_val - TARGET_U) <= TOLERANCE and abs(sc_val - TARGET_SC) <= TOLERANCE:
                    valid_glass_names.append(current_obj_name)
                    
                current_obj_type = None
                continue
            
            # Parse properties
            # Matches: KEY = VALUE or KEY = ( v1, v2 )
            parts = line.split('=')
            if len(parts) == 2:
                key = parts[0].strip()
                val_str = parts[1].strip()
                try:
                    val = float(val_str)
                    properties[key] = val
                except ValueError:
                    pass

    # Verify Criterion 1: New Glass Type Defined (30 pts)
    if valid_glass_names:
        score += 30
        feedback.append(f"Correct Glass Type defined ({len(valid_glass_names)} found: {valid_glass_names}) (+30)")
    else:
        feedback.append(f"No Glass Type found with U={TARGET_U} and SC={TARGET_SC} (+0)")
        # If no valid glass exists, they can't have assigned it. Stop here? 
        # We continue to see if they assigned *something* just for debug.

    # Step B: Check Window Assignments
    # We need to track context: Floor -> (Space/Wall) -> Window
    
    top_floor_windows_total = 0
    top_floor_windows_correct = 0
    lower_floor_windows_total = 0
    lower_floor_windows_incorrect = 0 # Using the new glass type
    
    current_floor_name = ""
    
    # Simple hierarchy tracking
    # "Floor" = FLOOR
    #    "Space" = SPACE ... ..
    #       "Wall" = EXTERIOR-WALL ... ..
    #          "Window" = WINDOW ... GLASS-TYPE = "Name" ... ..
    
    # We will process the file line by line again for hierarchy
    
    floor_pattern = re.compile(r'"([^"]+)"\s*=\s*FLOOR')
    window_pattern = re.compile(r'"([^"]+)"\s*=\s*WINDOW')
    
    inside_window = False
    current_window_glass = None
    
    for line in lines:
        line = line.split('$')[0].strip()
        if not line: continue
        
        # Track Floor
        fm = floor_pattern.match(line)
        if fm:
            current_floor_name = fm.group(1)
            continue
            
        # Track Window Start
        wm = window_pattern.match(line)
        if wm:
            inside_window = True
            current_window_glass = None # Reset
            continue
            
        # Inside Window
        if inside_window:
            if line == "..":
                inside_window = False
                # Analyze this window
                is_top = current_floor_name.startswith("T.") or "Top" in current_floor_name # flexible check
                is_lower = current_floor_name.startswith("G.") or current_floor_name.startswith("M.")
                
                # Check if this window uses one of our valid glass types
                uses_target_glass = current_window_glass in valid_glass_names
                
                if is_top:
                    top_floor_windows_total += 1
                    if uses_target_glass:
                        top_floor_windows_correct += 1
                elif is_lower:
                    lower_floor_windows_total += 1
                    if uses_target_glass:
                        lower_floor_windows_incorrect += 1
                continue
            
            # Check for GLASS-TYPE assignment
            if "GLASS-TYPE" in line and "=" in line:
                # Extract value between quotes
                val_part = line.split("=")[1].strip()
                if '"' in val_part:
                    current_window_glass = val_part.replace('"', '')
    
    # Verify Criterion 2: Top Floor Assignments (40 pts)
    if top_floor_windows_total > 0:
        ratio = top_floor_windows_correct / top_floor_windows_total
        pts = int(ratio * 40)
        score += pts
        if ratio == 1.0:
            feedback.append(f"All Top Floor windows updated ({top_floor_windows_correct}/{top_floor_windows_total}) (+40)")
        elif ratio > 0:
            feedback.append(f"Some Top Floor windows updated ({top_floor_windows_correct}/{top_floor_windows_total}) (+{pts})")
        else:
            feedback.append("No Top Floor windows updated (+0)")
    else:
        feedback.append("Parsing Error: No top floor windows found in model.")

    # Verify Criterion 3: Lower Floors Preserved (20 pts)
    if lower_floor_windows_incorrect == 0 and lower_floor_windows_total > 0:
        score += 20
        feedback.append("Lower floor windows preserved correctly (+20)")
    elif lower_floor_windows_total > 0:
        feedback.append(f"FAIL: {lower_floor_windows_incorrect} lower floor windows were incorrectly changed (+0)")
    
    # Final Verification
    # Threshold: 65 (Must define glass + assign to most top windows + preserve others + maybe sim)
    passed = score >= 65 and len(valid_glass_names) > 0
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "valid_glass_types": valid_glass_names,
            "top_total": top_floor_windows_total,
            "top_correct": top_floor_windows_correct,
            "lower_incorrect": lower_floor_windows_incorrect
        }
    }