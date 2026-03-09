#!/usr/bin/env python3
"""
Verifier for exterior_shading_south_windows task.

Logic:
1. Copy result JSON and .INP file from environment.
2. Check if Simulation was run (from JSON).
3. Parse .INP file:
    - Identify South-facing EXTERIOR-WALLs (Azimuth 180 +/- 45).
    - Identify WINDOWs belonging to those walls.
    - Verify OVERHANG-A, OVERHANG-B, OVERHANG-W on those windows.
4. Score based on coverage (percentage of south windows corrected) and parameters.
"""

import json
import os
import tempfile
import logging
import re
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_doe2_inp(content):
    """
    Simple parser for DOE-2 INP hierarchical structure.
    Returns a list of objects with type, name, and properties.
    """
    objects = []
    current_obj = None
    
    # Regex to identify object start: "Name" = TYPE
    obj_start_re = re.compile(r'^\s*"(.*?)"\s*=\s*([A-Z0-9-]+)\s*')
    
    lines = content.splitlines()
    for line in lines:
        line = line.split('..')[0].strip() # Remove comments and trim
        if not line:
            continue
            
        # Check for new object
        match = obj_start_re.match(line)
        if match:
            # Save previous object if exists
            if current_obj:
                objects.append(current_obj)
            
            name = match.group(1)
            obj_type = match.group(2)
            current_obj = {
                "name": name,
                "type": obj_type,
                "props": {},
                "children": [] # We'll handle hierarchy logically later or flatten
            }
        elif current_obj:
            # Parse properties: KEY = VALUE or KEY = ( v1, v2 )
            # Simplified: looking for KEY = VALUE
            # We handle simple assignments. 
            # Note: DOE-2 format can be multiline, this is a simplified parser sufficient for key params.
            parts = line.split('=')
            if len(parts) >= 2:
                key = parts[0].strip()
                val = parts[1].strip()
                current_obj["props"][key] = val
                
    if current_obj:
        objects.append(current_obj)
        
    return objects

def verify_exterior_shading_south_windows(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # 1. Retrieve Result JSON
    result_data = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp_json:
        try:
            copy_from_env("C:\\workspace\\task_result.json", tmp_json.name)
            tmp_json.close()
            with open(tmp_json.name, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            logger.error(f"Failed to load result JSON: {e}")
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results."}
        finally:
            if os.path.exists(tmp_json.name):
                os.unlink(tmp_json.name)

    # 2. Retrieve INP File
    inp_content = ""
    inp_path = result_data.get("inp_path", "")
    if inp_path:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.inp') as tmp_inp:
            try:
                copy_from_env(inp_path, tmp_inp.name)
                tmp_inp.close()
                with open(tmp_inp.name, 'r', encoding='utf-8', errors='ignore') as f:
                    inp_content = f.read()
            except Exception as e:
                logger.error(f"Failed to load INP file: {e}")
                return {"passed": False, "score": 0, "feedback": "Failed to retrieve project file (.inp)."}
            finally:
                if os.path.exists(tmp_inp.name):
                    os.unlink(tmp_inp.name)
    else:
        return {"passed": False, "score": 0, "feedback": "INP path not found in results."}

    # 3. Analyze Data
    score = 0
    feedback = []
    
    # Check Simulation (15 pts)
    sim_ran = result_data.get("sim_file_is_new", False)
    if sim_ran:
        score += 15
        feedback.append("Simulation ran successfully (+15).")
    else:
        feedback.append("Simulation NOT run (or .SIM file not new).")

    # Parse INP
    objects = parse_doe2_inp(inp_content)
    
    # Build Hierarchy: Wall -> Window
    # In DOE-2 INP, Windows follow Walls. We scan linearly.
    south_windows = []
    
    current_azimuth = None
    is_south_wall = False
    
    # Config
    target_azimuth = 180
    tolerance = 45
    
    for obj in objects:
        if obj["type"] == "EXTERIOR-WALL":
            # Check Azimuth
            az_val = obj["props"].get("AZIMUTH")
            if az_val:
                try:
                    az = float(az_val)
                    # Normalize to 0-360
                    az = az % 360
                    if abs(az - target_azimuth) <= tolerance:
                        is_south_wall = True
                    else:
                        is_south_wall = False
                except:
                    is_south_wall = False
            else:
                # If no azimuth, it inherits or uses coordinate system. 
                # For 4StoreyBuilding standard simplified geometry, walls usually have explicit azimuth.
                # Fallback: check name
                if "S" in obj["name"] and ("N" not in obj["name"]): # Rough heuristic if param missing
                    is_south_wall = True # Weak check, but better than nothing
                else:
                    is_south_wall = False
                    
        elif obj["type"] == "WINDOW":
            if is_south_wall:
                south_windows.append(obj)

    total_south_windows = len(south_windows)
    
    if total_south_windows == 0:
        return {"passed": False, "score": 0, "feedback": "Verification Error: Could not identify south-facing windows in model."}
    
    # Check parameters
    # Expected: OVERHANG-A = 0.5, OVERHANG-B = 3.0, OVERHANG-W = 0.0
    correct_count = 0
    
    for win in south_windows:
        props = win["props"]
        
        # Helper to parse float safe
        def get_float(k):
            try:
                return float(props.get(k, -999))
            except:
                return -999.0
        
        oa = get_float("OVERHANG-A")
        ob = get_float("OVERHANG-B")
        ow = get_float("OVERHANG-W")
        
        # Check tolerance 0.1
        ok_a = abs(oa - 0.5) < 0.1
        ok_b = abs(ob - 3.0) < 0.2
        ok_w = abs(ow - 0.0) < 0.1
        
        if ok_a and ok_b and ok_w:
            correct_count += 1
            
    # Scoring for windows (85 pts max)
    # Scaled by percentage of correct windows
    window_score = int((correct_count / total_south_windows) * 85)
    score += window_score
    
    feedback.append(f"South-facing windows corrected: {correct_count}/{total_south_windows} (+{window_score}).")
    
    # Final check
    passed = (score >= 60) and sim_ran
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }