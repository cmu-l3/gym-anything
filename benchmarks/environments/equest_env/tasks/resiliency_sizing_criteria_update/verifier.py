#!/usr/bin/env python3
"""
Verifier for resiliency_sizing_criteria_update task.

Checks:
1. Simulation ran during the session (new .SIM file).
2. Cooling Design Day parameters updated (DB=102, WB=75).
3. Ground Floor (G.*) systems Cooling Sizing Ratio updated to 1.25.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants
EXPECTED_DB = 102.0
EXPECTED_WB = 75.0
EXPECTED_RATIO = 1.25
TOLERANCE_TEMP = 0.5
TOLERANCE_RATIO = 0.01

def parse_inp_file(content):
    """
    Parses eQUEST .inp file content to extract Design Days and Systems.
    Returns a dictionary with parsed data.
    """
    data = {
        "design_days": [],
        "systems": []
    }
    
    # Clean content: remove comments strings inside quotes can be tricky, 
    # but eQUEST INP structure is fairly line-oriented for properties.
    
    # Regex for Design Day
    # Pattern: "Name" = DESIGN-DAY ... .. ..
    dd_pattern = re.compile(r'"([^"]+)"\s*=\s*DESIGN-DAY\s*(.*?)\.\.', re.DOTALL)
    
    for match in dd_pattern.finditer(content):
        name = match.group(1)
        block = match.group(2)
        
        # Extract Type
        type_match = re.search(r'TYPE\s*=\s*([A-Za-z0-9\-]+)', block)
        dd_type = type_match.group(1) if type_match else "UNKNOWN"
        
        # Extract DB
        db_match = re.search(r'MAX-DRY-BULB\s*=\s*([\d\.]+)', block)
        max_db = float(db_match.group(1)) if db_match else None
        
        # Extract WB
        wb_match = re.search(r'WET-BULB-AT-MAX\s*=\s*([\d\.]+)', block)
        wb_max = float(wb_match.group(1)) if wb_match else None
        
        data["design_days"].append({
            "name": name,
            "type": dd_type,
            "max_db": max_db,
            "wb_at_max": wb_max
        })

    # Regex for Systems
    # Pattern: "Name" = SYSTEM ... .. ..
    sys_pattern = re.compile(r'"([^"]+)"\s*=\s*SYSTEM\s*(.*?)\.\.', re.DOTALL)
    
    for match in sys_pattern.finditer(content):
        name = match.group(1)
        block = match.group(2)
        
        # Extract Sizing Ratio
        ratio_match = re.search(r'COOLING-SIZING-RATIO\s*=\s*([\d\.]+)', block)
        ratio = float(ratio_match.group(1)) if ratio_match else 1.0 # Default is often 1.0 or 1.15 depending on version, assuming 1.0 if missing
        
        # Check if explicitly set (if missing in INP, it uses default)
        # We only care if the agent set it. If missing, it's definitely not 1.25 (unless default changed, which is unlikely)
        
        data["systems"].append({
            "name": name,
            "cooling_sizing_ratio": ratio
        })
        
    return data

def verify_resiliency_sizing_criteria_update(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # 1. Fetch Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Fetch Project File (.inp)
    project_path = result_data.get("project_path")
    temp_inp = tempfile.NamedTemporaryFile(delete=False, suffix='.inp')
    inp_content = ""
    try:
        copy_from_env(project_path, temp_inp.name)
        with open(temp_inp.name, 'r', encoding='utf-8', errors='ignore') as f:
            inp_content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve project file: {e}"}
    finally:
        if os.path.exists(temp_inp.name):
            os.unlink(temp_inp.name)

    # Parse INP data
    parsed_data = parse_inp_file(inp_content)
    
    score = 0
    feedback = []
    
    # CRITERION 1: Simulation Ran (10 pts)
    if result_data.get("sim_file_created", False):
        score += 10
        feedback.append("Simulation ran successfully (+10).")
    else:
        feedback.append("Simulation did not run or no new .SIM file found.")

    # CRITERION 2: Design Day Update (30 pts)
    # Looking for ANY cooling design day with correct values
    dd_passed = False
    for dd in parsed_data["design_days"]:
        # Check values if they exist
        if dd["max_db"] is not None and dd["wb_at_max"] is not None:
            db_ok = abs(dd["max_db"] - EXPECTED_DB) <= TOLERANCE_TEMP
            wb_ok = abs(dd["wb_at_max"] - EXPECTED_WB) <= TOLERANCE_TEMP
            
            if db_ok and wb_ok:
                dd_passed = True
                score += 30
                feedback.append(f"Design Day '{dd['name']}' updated correctly ({dd['max_db']} F / {dd['wb_at_max']} F) (+30).")
                break
    
    if not dd_passed:
        # Check for partial credit
        best_dd = None
        for dd in parsed_data["design_days"]:
            if dd["max_db"] is not None and abs(dd["max_db"] - EXPECTED_DB) <= TOLERANCE_TEMP:
                score += 15
                feedback.append(f"Design Day '{dd['name']}' Dry Bulb correct, but Wet Bulb incorrect (+15).")
                break
            elif dd["wb_at_max"] is not None and abs(dd["wb_at_max"] - EXPECTED_WB) <= TOLERANCE_TEMP:
                score += 15
                feedback.append(f"Design Day '{dd['name']}' Wet Bulb correct, but Dry Bulb incorrect (+15).")
                break
        if not feedback or "Design Day" not in feedback[-1]:
            feedback.append("No Cooling Design Day found with correct parameters.")

    # CRITERION 3: Ground Floor Systems Sizing Ratio (60 pts total -> 12 per system)
    # Identify Ground Floor systems (match G. pattern)
    target_systems = [s for s in parsed_data["systems"] if "G." in s["name"]]
    
    if not target_systems:
        feedback.append("Critical Error: Could not find Ground Floor (G.*) systems in project file.")
    else:
        systems_correct = 0
        systems_total = len(target_systems)
        # Cap at 5 systems for scoring if there are more for some reason
        systems_to_score = target_systems[:5] 
        
        for sys in systems_to_score:
            ratio = sys["cooling_sizing_ratio"]
            if abs(ratio - EXPECTED_RATIO) <= TOLERANCE_RATIO:
                systems_correct += 1
        
        # Calculate points: 60 pts distributed among 5 systems = 12 pts each
        points_per_system = 12
        sys_score = systems_correct * points_per_system
        score += sys_score
        
        if systems_correct == len(systems_to_score):
            feedback.append(f"All {systems_correct} Ground Floor systems updated to Sizing Ratio {EXPECTED_RATIO} (+{sys_score}).")
        else:
            feedback.append(f"{systems_correct}/{len(systems_to_score)} Ground Floor systems updated correctly (+{sys_score}).")

    # Final Pass/Fail
    passed = (score >= 60) and result_data.get("sim_file_created", False)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }