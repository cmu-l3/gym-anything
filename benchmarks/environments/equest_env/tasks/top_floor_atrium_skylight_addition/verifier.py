#!/usr/bin/env python3
"""
Verifier for top_floor_atrium_skylight_addition task.
Parses the eQUEST .INP file to verify the creation of a skylight on the correct roof.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Paths in the Windows environment
WIN_RESULT_PATH = "C:\\Users\\Docker\\task_result.json"
WIN_INP_PATH = "C:\\Users\\Docker\\Documents\\eQUEST 3-65 Projects\\4StoreyBuilding\\4StoreyBuilding.inp"

def parse_inp_for_skylight(inp_content, target_zone="T.C35"):
    """
    Parses INP content to find a skylight on the roof of the target zone.
    
    Structure to find:
    SPACE with u-name = target_zone
      ...
      EXTERIOR-WALL with TILT = 0 (The Roof)
        ...
        WINDOW (The Skylight)
           HEIGHT = 20
           WIDTH = 20
           X = 15
           Y = 15
    """
    lines = inp_content.splitlines()
    
    current_space = None
    current_wall_tilt = None
    current_wall_is_roof = False
    
    skylight_found = False
    skylight_details = {}
    
    # Simple state machine parser
    # Note: eQUEST INP files use " = " for assignment and keywords like "SPACE", "EXTERIOR-WALL", "WINDOW"
    # Indentation usually implies hierarchy, but ".." terminates a block.
    
    # We will look for the specific sequence of parents.
    
    for i, line in enumerate(lines):
        line = line.strip()
        
        # Detect Space
        # Format: "Zone Name" = SPACE
        space_match = re.search(r'"([^"]+)"\s*=\s*SPACE', line)
        if space_match:
            current_space = space_match.group(1)
            current_wall_tilt = None
            current_wall_is_roof = False
            continue
            
        # Detect Exterior Wall
        # Format: "Wall Name" = EXTERIOR-WALL
        if re.search(r'=\s*EXTERIOR-WALL', line):
            # We are entering a wall. Reset roof status.
            current_wall_is_roof = False
            current_wall_tilt = None
            continue
            
        # Detect Tilt
        tilt_match = re.search(r'TILT\s*=\s*([0-9\.]+)', line)
        if tilt_match:
            current_wall_tilt = float(tilt_match.group(1))
            if current_wall_tilt < 5: # Allow small tolerance for flat roof
                current_wall_is_roof = True
            else:
                current_wall_is_roof = False
                
        # Detect Window
        # Format: "Window Name" = WINDOW
        if re.search(r'=\s*WINDOW', line):
            # Check if we are in the right place
            if current_space == target_zone and current_wall_is_roof:
                # We found a window on the roof of the target zone!
                # Now lets parse its properties from subsequent lines until ".."
                
                props = {'HEIGHT': 0, 'WIDTH': 0, 'X': 0, 'Y': 0, 'GLASS-TYPE': ''}
                
                # Scan ahead for properties
                for j in range(i + 1, len(lines)):
                    subline = lines[j].strip()
                    if subline.startswith(".."):
                        break
                    
                    # Extract numeric properties
                    for key in ['HEIGHT', 'WIDTH', 'X', 'Y']:
                        val_match = re.search(rf'{key}\s*=\s*([0-9\.]+)', subline)
                        if val_match:
                            props[key] = float(val_match.group(1))
                            
                    # Extract Glass Type
                    gt_match = re.search(r'GLASS-TYPE\s*=\s*"([^"]+)"', subline)
                    if gt_match:
                        props['GLASS-TYPE'] = gt_match.group(1)
                
                # Verify if this looks like our skylight (approx dimensions)
                # We'll return the first one that matches the criteria roughly, or just the last one found
                if props['HEIGHT'] > 0 and props['WIDTH'] > 0:
                    skylight_found = True
                    skylight_details = props
                    return skylight_found, skylight_details

    return skylight_found, skylight_details

def verify_top_floor_atrium_skylight_addition(traj, env_info, task_info):
    """
    Verifies that the agent added a 20x20 skylight to T.C35 roof and ran the simulation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # 1. Load basic result JSON (Simulation status)
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(WIN_RESULT_PATH, temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Retrieve and Parse INP file
    inp_content = ""
    temp_inp = tempfile.NamedTemporaryFile(delete=False, suffix='.inp')
    try:
        copy_from_env(WIN_INP_PATH, temp_inp.name)
        with open(temp_inp.name, 'r', encoding='latin-1') as f: # INP files often have legacy encoding
            inp_content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve project INP file: {str(e)}"}
    finally:
        if os.path.exists(temp_inp.name):
            os.unlink(temp_inp.name)

    # 3. Analyze Data
    score = 0
    feedback_parts = []
    
    # Criterion 1: Simulation ran (10 pts)
    if task_result.get('sim_file_is_new', False):
        score += 10
        feedback_parts.append("Simulation ran successfully (+10)")
    else:
        feedback_parts.append("Simulation did not run or file not updated")

    # Criterion 2-5: Skylight properties
    target_zone = "T.C35"
    skylight_found, props = parse_inp_for_skylight(inp_content, target_zone)
    
    if skylight_found:
        # Parent check (Implicit in parser finding it under T.C35/Roof)
        score += 30 # "Parent is Correct (Roof)"
        feedback_parts.append(f"Skylight found on {target_zone} Roof (+30)")
        
        # Check Existence/Basic Validity
        score += 20 # "Skylight Exists"
        feedback_parts.append("Window object created (+20)")
        
        # Dimensions Check (Area)
        h = props.get('HEIGHT', 0)
        w = props.get('WIDTH', 0)
        area = h * w
        if 380 <= area <= 420: # 400 sqft ± 5%
            score += 20
            feedback_parts.append(f"Dimensions correct ({h}x{w}) (+20)")
        else:
            feedback_parts.append(f"Dimensions incorrect (Area: {area} sqft, Expected: 400)")
            
        # Position Check
        x = props.get('X', 0)
        y = props.get('Y', 0)
        if 14.5 <= x <= 15.5 and 14.5 <= y <= 15.5:
            score += 10
            feedback_parts.append(f"Position correct (X:{x}, Y:{y}) (+10)")
        else:
            feedback_parts.append(f"Position incorrect (X:{x}, Y:{y}, Expected: 15,15)")
            
        # Glass Type Check
        if props.get('GLASS-TYPE'):
            score += 10
            feedback_parts.append("Glass type assigned (+10)")
        else:
            feedback_parts.append("No glass type assigned")
            
    else:
        feedback_parts.append(f"No skylight found on roof of {target_zone}")

    # Pass logic
    passed = (score >= 70) and task_result.get('sim_file_is_new', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }