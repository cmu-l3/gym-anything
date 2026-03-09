#!/usr/bin/env python3
"""
Verifier for perimeter_hvac_cooling_sizing_adjustment task.

The verifier checks:
1. Did the agent run the simulation? (Anti-gaming)
2. Are all 12 Perimeter systems set to COOL-SIZING-RATI = 1.0?
3. Are Core systems UNTOUCHED (not 1.0)?
4. Is HEAT-SIZING-RATI UNTOUCHED (not 1.0)?
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_perimeter_hvac_sizing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Define paths
    remote_result_path = r"C:\Users\Docker\perimeter_hvac_result.json"
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(remote_result_path, temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task results. Ensure you saved the project and allowed the script to run. Error: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring Variables
    score = 0
    feedback = []
    
    # 1. Check Simulation (10 pts)
    if result_data.get("sim_is_new", False):
        score += 10
        feedback.append("Simulation run confirmed (+10).")
    else:
        feedback.append("Simulation NOT run or stale results found (0/10).")

    systems = result_data.get("systems", {})
    
    # Classify Systems
    perimeter_systems = []
    core_systems = []
    
    # Regex for naming convention: G.S1, T.E32 etc. (Directional letters S, E, N, W)
    # Core usually has 'C' or 'Core'
    for name, data in systems.items():
        # Skip if not PSZ or generic definition
        if data.get("TYPE") != "PSZ":
            continue
            
        # Determine orientation based on name
        # Exclude Core
        if re.search(r'[._](C|Core)\d*', name, re.IGNORECASE):
            core_systems.append((name, data))
        elif re.search(r'[._](S|E|N|W)\d+', name, re.IGNORECASE):
            perimeter_systems.append((name, data))
    
    # 2. Check Perimeter Systems (60 pts)
    # 12 systems total. 5 pts each.
    perimeter_correct = 0
    perimeter_total = len(perimeter_systems)
    
    for name, data in perimeter_systems:
        val = data.get("COOL-SIZING-RATI", "default")
        try:
            val_float = float(val)
            if 0.99 <= val_float <= 1.01:
                perimeter_correct += 1
            else:
                feedback.append(f"System {name}: COOL-SIZING-RATI is {val}, expected 1.0.")
        except ValueError:
            feedback.append(f"System {name}: COOL-SIZING-RATI is default/missing, expected 1.0.")

    perimeter_score = 0
    if perimeter_total > 0:
        perimeter_score = int((perimeter_correct / perimeter_total) * 60)
    
    score += perimeter_score
    feedback.append(f"Perimeter systems correct: {perimeter_correct}/{perimeter_total} (+{perimeter_score}).")

    # 3. Check Core Systems Preservation (15 pts)
    # Should NOT be 1.0 (defaults are usually 1.15 or 1.2)
    core_preserved = 0
    core_total = len(core_systems)
    
    for name, data in core_systems:
        val = data.get("COOL-SIZING-RATI", "default")
        is_one = False
        try:
            if float(val) == 1.0:
                is_one = True
        except ValueError:
            pass # Default is safe
            
        if not is_one:
            core_preserved += 1
        else:
            feedback.append(f"Core System {name}: Incorrectly modified to 1.0.")

    core_score = 0
    if core_total > 0:
        core_score = int((core_preserved / core_total) * 15)
        
    score += core_score
    if core_preserved == core_total:
        feedback.append("Core systems preserved (+15).")
    else:
        feedback.append(f"Core systems modified incorrectly: {core_total - core_preserved}/{core_total}.")

    # 4. Check Heating Preservation (15 pts)
    # Check all modified perimeter systems to ensure HEAT-SIZING-RATI wasn't also changed to 1.0
    heating_preserved_count = 0
    
    for name, data in perimeter_systems:
        val = data.get("HEAT-SIZING-RATI", "default")
        is_one = False
        try:
            if float(val) == 1.0:
                is_one = True
        except ValueError:
            pass # Default is safe
            
        if not is_one:
            heating_preserved_count += 1
    
    heating_score = 0
    if perimeter_total > 0:
        heating_score = int((heating_preserved_count / perimeter_total) * 15)
        
    score += heating_score
    if heating_preserved_count < perimeter_total:
         feedback.append(f"Heating sizing incorrectly modified on {perimeter_total - heating_preserved_count} systems.")
    else:
         feedback.append("Heating parameters preserved (+15).")

    # Final Verdict
    # Threshold: 70 pts AND Simulation Must Be Run
    passed = (score >= 70) and result_data.get("sim_is_new", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }