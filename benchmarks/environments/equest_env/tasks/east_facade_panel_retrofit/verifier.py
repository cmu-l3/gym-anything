#!/usr/bin/env python3
"""
Verifier for East Facade High-R Panel Retrofit task.
Parses the eQUEST .inp file to verify:
1. Material 'VacuPanel-R20' created with R=20.
2. Construction 'East-Retrofit-Wall' created using that material.
3. East-facing walls assigned to this construction.
4. Non-East walls NOT assigned (anti-gaming).
5. Simulation run.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_inp_file(content):
    """
    Parses DOE-2 INP content to extract Materials, Constructions, and Wall assignments.
    """
    # Regex patterns
    # Material: "Name" = MATERIAL ... RESISTANCE = X ... ..
    # Note: DOE-2 files are loosely structured. Commands end with ..
    
    materials = {}
    constructions = {}
    walls = []

    # Helper to find blocks
    # Looking for: "Name" = COMMAND-TYPE
    block_pattern = re.compile(r'"([^"]+)"\s*=\s*([A-Z-]+)(.*?)\.\.', re.DOTALL)
    
    for match in block_pattern.finditer(content):
        name = match.group(1)
        type_ = match.group(2)
        body = match.group(3)
        
        if type_ == "MATERIAL":
            res_match = re.search(r'RESISTANCE\s*=\s*([0-9.]+)', body)
            resistance = float(res_match.group(1)) if res_match else 0.0
            materials[name] = {'resistance': resistance}
            
        elif type_ == "CONSTRUCTION":
            # LAYERS = ( "Layer1", "Layer2" )
            layers_match = re.search(r'LAYERS\s*=\s*\((.*?)\)', body, re.DOTALL)
            layers = []
            if layers_match:
                # Extract quoted strings inside parens
                layers = re.findall(r'"([^"]+)"', layers_match.group(1))
            constructions[name] = {'layers': layers}
            
        elif type_ == "EXTERIOR-WALL":
            # Need to find the assigned construction
            cons_match = re.search(r'CONSTRUCTION\s*=\s*"([^"]+)"', body)
            cons_name = cons_match.group(1) if cons_match else None
            walls.append({'name': name, 'construction': cons_name})
            
    return materials, constructions, walls

def verify_east_facade_panel_retrofit(traj, env_info, task_info):
    """
    Verify the task completion.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON and INP File
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_inp = tempfile.NamedTemporaryFile(delete=False, suffix='.inp')
    
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
            
        # Get the INP path from result or metadata
        inp_path = result.get('inp_file_path', 'C:\\Users\\Docker\\Documents\\eQUEST 3-65 Projects\\4StoreyBuilding\\4StoreyBuilding.inp')
        copy_from_env(inp_path, temp_inp.name)
        with open(temp_inp.name, 'r', encoding='utf-8', errors='ignore') as f:
            inp_content = f.read()
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task files: {e}"}
    finally:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)
        if os.path.exists(temp_inp.name): os.unlink(temp_inp.name)

    # 2. Parse INP
    materials, constructions, walls = parse_inp_file(inp_content)
    
    score = 0
    feedback = []
    
    # Criteria 1: Simulation Run (10 pts)
    if result.get('sim_file_is_new', False):
        score += 10
        feedback.append("Simulation ran successfully (+10).")
    else:
        feedback.append("Simulation was NOT run during the task.")

    # Criteria 2: Material Created (20 pts)
    mat_name = "VacuPanel-R20"
    if mat_name in materials:
        r_val = materials[mat_name]['resistance']
        if 19.9 <= r_val <= 20.1:
            score += 20
            feedback.append(f"Material '{mat_name}' created with correct Resistance ({r_val}) (+20).")
        else:
            score += 10
            feedback.append(f"Material '{mat_name}' created but Resistance is {r_val} (expected 20.0) (+10).")
    else:
        feedback.append(f"Material '{mat_name}' NOT found.")

    # Criteria 3: Construction Created (20 pts)
    cons_name = "East-Retrofit-Wall"
    if cons_name in constructions:
        layers = constructions[cons_name]['layers']
        if mat_name in layers:
            score += 20
            feedback.append(f"Construction '{cons_name}' created and uses '{mat_name}' (+20).")
        else:
            score += 10
            feedback.append(f"Construction '{cons_name}' created but does not use correct material layer (+10).")
    else:
        feedback.append(f"Construction '{cons_name}' NOT found.")

    # Criteria 4: Wall Assignments (40 pts)
    # Identify East walls: Name typically contains ".E" (e.g., "G.E2 Wall")
    # Identify Non-East walls: Name contains ".N", ".S", ".W"
    
    east_walls = [w for w in walls if re.search(r'\.E\d*', w['name'], re.IGNORECASE)]
    other_walls = [w for w in walls if re.search(r'\.[NSW]\d*', w['name'], re.IGNORECASE)]
    
    if not east_walls:
        feedback.append("Could not identify East walls by name pattern. Parsing error?")
    
    correct_east_assignments = 0
    for w in east_walls:
        if w['construction'] == cons_name:
            correct_east_assignments += 1
            
    # Score for East Assignments (max 40)
    if east_walls:
        east_fraction = correct_east_assignments / len(east_walls)
        east_points = int(east_fraction * 40)
        score += east_points
        feedback.append(f"Assigned construction to {correct_east_assignments}/{len(east_walls)} East walls (+{east_points}).")
    
    # Criteria 5: Preservation of Other Walls (10 pts)
    # Anti-gaming: Ensure they didn't just change the default global construction
    incorrect_other_assignments = 0
    for w in other_walls:
        if w['construction'] == cons_name:
            incorrect_other_assignments += 1
            
    if len(other_walls) > 0 and incorrect_other_assignments == 0:
        score += 10
        feedback.append("Other orientations preserved correctly (+10).")
    elif len(other_walls) > 0:
        feedback.append(f"Warning: Modified {incorrect_other_assignments} non-East walls (should have stayed original).")
        
    # Final check
    passed = (score >= 65) and (result.get('sim_file_is_new', False))
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }