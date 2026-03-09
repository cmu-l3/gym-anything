#!/usr/bin/env python3
"""
Verifier for ground_floor_retail_conversion task in eQUEST.

Verification criteria:
1. Annual simulation ran during task session (Check .SIM file timestamp).
2. All 5 Ground Floor Spaces (G.*) have AREA/PERSON = 40.
3. All 5 Ground Floor Systems (G.*) have MIN-OUTSIDE-AIR = 750.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Paths inside the container
CONTAINER_RESULT_PATH = "C:\\Users\\Docker\\ground_floor_retail_conversion_result.json"
CONTAINER_INP_PATH = "C:\\Users\\Docker\\Documents\\eQUEST 3-65 Projects\\4StoreyBuilding\\4StoreyBuilding.inp"


def parse_inp_file(content):
    """
    Parses DOE-2.2 INP format to extract Spaces and Systems.
    Returns dictionaries of spaces and systems with their parameters.
    """
    spaces = {}
    systems = {}
    
    current_block_name = None
    current_block_type = None
    
    # Regex to identify block headers: "Name" = TYPE
    header_pattern = re.compile(r'^"([^"]+)"\s*=\s*([A-Z0-9-]+)')
    
    lines = content.splitlines()
    for line in lines:
        line = line.strip()
        
        # Skip comments
        if line.startswith('$'):
            continue
            
        # Check for block start
        m_header = header_pattern.match(line)
        if m_header:
            current_block_name = m_header.group(1)
            current_block_type = m_header.group(2)
            continue
            
        # Check for block end
        if line == "..":
            current_block_name = None
            current_block_type = None
            continue
            
        # Parse parameters if inside a relevant block
        if current_block_name and "=" in line:
            parts = line.split("=", 1)
            key = parts[0].strip()
            val = parts[1].strip()
            
            # Remove inline comments if any
            if "$" in val:
                val = val.split("$")[0].strip()
                
            if current_block_type == "SPACE":
                if current_block_name not in spaces:
                    spaces[current_block_name] = {}
                spaces[current_block_name][key] = val
                
            elif current_block_type == "SYSTEM":
                if current_block_name not in systems:
                    systems[current_block_name] = {}
                systems[current_block_name][key] = val
                
    return spaces, systems


def verify_ground_floor_retail_conversion(traj, env_info, task_info):
    """
    Verifies the eQUEST task results.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Metadata targets
    metadata = task_info.get('metadata', {})
    target_area = metadata.get('target_area_per_person', 40)
    target_oa = metadata.get('target_min_outside_air', 750)
    tol_area = metadata.get('tolerance_area', 1.0)
    tol_oa = metadata.get('tolerance_air', 25)

    # 1. Load JSON Result (Timestamps)
    result_json = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(CONTAINER_RESULT_PATH, temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_json = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve verification data from container."}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Load INP File (Project Data)
    inp_content = ""
    temp_inp = tempfile.NamedTemporaryFile(delete=False, suffix='.inp')
    try:
        copy_from_env(CONTAINER_INP_PATH, temp_inp.name)
        with open(temp_inp.name, 'r', encoding='latin-1') as f: # INP files often use simple encodings
            inp_content = f.read()
    except Exception as e:
        logger.error(f"Failed to load INP file: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve project file (.inp) for verification."}
    finally:
        if os.path.exists(temp_inp.name):
            os.unlink(temp_inp.name)

    # Parse INP Data
    spaces, systems = parse_inp_file(inp_content)
    
    feedback_parts = []
    score = 0
    
    # ---------------------------------------------------------
    # Criterion 1: Simulation Ran (10 pts)
    # ---------------------------------------------------------
    sim_is_new = result_json.get('sim_file_is_new', False)
    if sim_is_new:
        score += 10
        feedback_parts.append("Simulation ran successfully (+10).")
    else:
        feedback_parts.append("Simulation not run or output not saved during task.")

    # ---------------------------------------------------------
    # Criterion 2: Check Ground Floor Spaces (45 pts total, 9 per space)
    # ---------------------------------------------------------
    g_spaces = [name for name in spaces.keys() if name.startswith("G.")]
    valid_spaces = 0
    
    for name in g_spaces:
        # Get AREA/PERSON
        val_str = spaces[name].get('AREA/PERSON', '0')
        try:
            val = float(val_str)
            if abs(val - target_area) <= tol_area:
                valid_spaces += 1
        except ValueError:
            pass
            
    # Normalize score for spaces
    # Expecting 5 spaces. If more found (e.g. core/perim), verify them all?
    # Usually G.S1, G.E2, G.N3, G.W4, G.C5 (5 spaces).
    expected_spaces = 5
    space_score = 0
    if valid_spaces >= expected_spaces:
        space_score = 45
        feedback_parts.append(f"All {valid_spaces} Ground floor spaces updated correctly (+45).")
    elif valid_spaces > 0:
        space_score = int((valid_spaces / expected_spaces) * 45)
        feedback_parts.append(f"{valid_spaces}/{expected_spaces} Ground floor spaces updated correctly (+{space_score}).")
    else:
        feedback_parts.append("No ground floor spaces updated correctly.")
        
    score += space_score

    # ---------------------------------------------------------
    # Criterion 3: Check Ground Floor Systems (45 pts total, 9 per system)
    # ---------------------------------------------------------
    g_systems = [name for name in systems.keys() if name.startswith("G.")]
    valid_systems = 0
    
    for name in g_systems:
        # Get MIN-OUTSIDE-AIR
        val_str = systems[name].get('MIN-OUTSIDE-AIR', '0')
        try:
            val = float(val_str)
            if abs(val - target_oa) <= tol_oa:
                valid_systems += 1
        except ValueError:
            pass
            
    expected_systems = 5
    system_score = 0
    if valid_systems >= expected_systems:
        system_score = 45
        feedback_parts.append(f"All {valid_systems} Ground floor systems updated correctly (+45).")
    elif valid_systems > 0:
        system_score = int((valid_systems / expected_systems) * 45)
        feedback_parts.append(f"{valid_systems}/{expected_systems} Ground floor systems updated correctly (+{system_score}).")
    else:
        feedback_parts.append("No ground floor systems updated correctly.")
        
    score += system_score

    # Final Pass Logic
    # Pass if score >= 60 AND simulation ran
    passed = (score >= 60) and sim_is_new
    
    if not sim_is_new and score >= 60:
        feedback_parts.append("FAIL: Task completed but simulation was not run/saved.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }