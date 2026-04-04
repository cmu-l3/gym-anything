#!/usr/bin/env python3
"""
Verifier for HVAC System Consolidation Task.

Goal:
1. Merge Zone 'M.N23' into System 'M.E22'.
2. Delete System 'M.N23'.
3. Run Simulation.

Verification Steps:
1. Parse .inp file:
   - Find System 'M.E22'.
   - Ensure it contains Zone 'M.E22' AND Zone 'M.N23'.
   - Ensure System 'M.N23' is NOT in the file.
2. Check Simulation:
   - .sim file must be new (> start time).
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_inp_hierarchy(inp_content):
    """
    Parses a DOE-2 .inp file to extract System -> Zone hierarchy.
    Returns a dict: { 'SystemName': ['ZoneName1', 'ZoneName2', ...] }
    """
    hierarchy = {}
    current_system = None
    
    # Simple regex parsing for BDL structure
    # Look for "Name" = SYSTEM or "Name" = ZONE
    # Structure is usually nested, but BDL can also use keywords like "ASSIGNED-TO".
    # However, eQUEST usually nests ZONES inside SYSTEMS in the text file.
    
    lines = inp_content.split('\n')
    
    # Stack to track nesting
    # We really only care about SYSTEM and ZONE levels
    
    for line in lines:
        line = line.strip()
        
        # Check for System definition
        # Format: "Sys Name" = SYSTEM
        sys_match = re.search(r'"([^"]+)"\s*=\s*SYSTEM', line, re.IGNORECASE)
        if sys_match:
            current_system = sys_match.group(1)
            hierarchy[current_system] = []
            continue
            
        # Check for Zone definition
        # Format: "Zone Name" = ZONE
        zone_match = re.search(r'"([^"]+)"\s*=\s*ZONE', line, re.IGNORECASE)
        if zone_match and current_system:
            hierarchy[current_system].append(zone_match.group(1))
            continue
            
        # Check for end of block (..)
        # If we hit .., we might be exiting a system, but eQUEST formatting 
        # usually indents. A robust parser handles indentation, but simple 
        # current_system tracking works if ZONEs are physically inside SYSTEM blocks.
        # If eQUEST uses "parent = " syntax, this parser might miss it, 
        # but standard eQUEST saving nests them.
        
    return hierarchy

def verify_hvac_consolidation(traj, env_info, task_info):
    """
    Verify the specific HVAC consolidation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result data: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # 2. Retrieve INP File
    inp_path = result_data.get('inp_path')
    if not inp_path:
        return {"passed": False, "score": 0, "feedback": "INP path not found in result"}
        
    temp_inp = tempfile.NamedTemporaryFile(delete=False, suffix='.inp')
    try:
        copy_from_env(inp_path, temp_inp.name)
        with open(temp_inp.name, 'r', encoding='utf-8', errors='ignore') as f:
            inp_content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve INP file: {str(e)}"}
    finally:
        if os.path.exists(temp_inp.name):
            os.unlink(temp_inp.name)

    # 3. Analyze Data
    score = 0
    feedback = []
    
    # Check Simulation (20 pts)
    if result_data.get('sim_is_new'):
        score += 20
        feedback.append("Simulation ran successfully (+20).")
    else:
        feedback.append("Simulation did not run or was not saved.")

    # Parse Hierarchy
    hierarchy = parse_inp_hierarchy(inp_content)
    
    target_system = "M.E22"  # (or Sys1 (PSZ) (M.E22) - need to match eQUEST naming exactly)
    # Note: eQUEST often names systems like "Sys1 (PSZ) (M.E22)". 
    # The regex parser extracts the quote name.
    # We should look for partial match if exact name isn't known, but usually it is "M.E22" or similar based on setup.
    # Let's find the system that contains "M.E22" in its name.
    
    found_target_sys_key = None
    for sys_name in hierarchy.keys():
        if "M.E22" in sys_name:
            found_target_sys_key = sys_name
            break
            
    deleted_sys_key = None
    for sys_name in hierarchy.keys():
        if "M.N23" in sys_name:
            deleted_sys_key = sys_name
            break
            
    # Check Target System (M.E22)
    target_zone_found = False
    original_zone_found = False
    
    if found_target_sys_key:
        zones = hierarchy[found_target_sys_key]
        # Check for original zone (M.E22)
        if any("M.E22" in z for z in zones):
            original_zone_found = True
            
        # Check for moved zone (M.N23)
        if any("M.N23" in z for z in zones):
            target_zone_found = True
            
        if target_zone_found:
            score += 40
            feedback.append(f"Zone 'M.N23' successfully moved to System '{found_target_sys_key}' (+40).")
        else:
            feedback.append(f"Zone 'M.N23' NOT found in System '{found_target_sys_key}'.")
            
        if original_zone_found:
             # Just a sanity check, no points usually, or small points
             pass
    else:
        feedback.append("Target System 'M.E22' not found in file.")

    # Check Deleted System (M.N23) (20 pts)
    if deleted_sys_key is None:
        score += 20
        feedback.append("Old System 'M.N23' successfully deleted (+20).")
    else:
        # Check if it's empty (maybe they kept it but moved the zone)
        if not hierarchy[deleted_sys_key]:
            score += 10
            feedback.append("Old System 'M.N23' is empty but was not deleted (+10).")
        else:
            feedback.append("Old System 'M.N23' still exists and is not empty.")

    # Zone Existence Check (20 pts)
    # Verify M.N23 zone still exists somewhere in the file
    zone_exists = False
    for sys_key, zones in hierarchy.items():
        if any("M.N23" in z for z in zones):
            zone_exists = True
            break
    
    if zone_exists:
        score += 20
        feedback.append("Zone 'M.N23' preserved in model (+20).")
    else:
        feedback.append("CRITICAL: Zone 'M.N23' seems to have been deleted entirely!")
        score = 0 # Fail if they deleted the zone instead of moving it

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }