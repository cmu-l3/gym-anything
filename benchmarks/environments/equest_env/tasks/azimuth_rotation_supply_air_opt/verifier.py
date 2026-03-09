#!/usr/bin/env python3
"""
Verifier for azimuth_rotation_supply_air_opt task.

Verification Steps:
1. Copy task_result.json from env to check if simulation ran.
2. Copy 4StoreyBuilding.inp from env to verify model parameters.
3. Parse INP for AZIMUTH = 90.
4. Parse INP for COOL-SET-T = 58 on G.* systems.

Scoring:
- Simulation Ran: 20 pts
- Azimuth Correct: 20 pts
- Systems Updated: 12 pts each (5 systems total) = 60 pts
Total: 100 pts
Pass: >= 60 pts AND Simulation Ran.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_azimuth_rotation_supply_air_opt(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function not available"}

    # Define paths
    result_json_path = "C:\\Users\\Docker\\task_result.json"
    inp_file_path = "C:\\Users\\Docker\\Documents\\eQUEST 3-65 Projects\\4StoreyBuilding\\4StoreyBuilding.inp"

    # Temporary files on host
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_inp = tempfile.NamedTemporaryFile(delete=False, suffix='.inp')
    
    score = 0
    feedback_parts = []
    
    try:
        # 1. Retrieve Result JSON
        try:
            copy_from_env(result_json_path, temp_result.name)
            with open(temp_result.name, 'r') as f:
                res_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

        sim_ran = res_data.get('sim_ran', False)
        if sim_ran:
            score += 20
            feedback_parts.append("Simulation ran successfully (+20)")
        else:
            feedback_parts.append("Simulation did not run or file is stale")

        # 2. Retrieve INP File
        try:
            copy_from_env(inp_file_path, temp_inp.name)
            with open(temp_inp.name, 'r', encoding='latin-1') as f:
                inp_content = f.read()
        except Exception as e:
            return {
                "passed": False, 
                "score": score, 
                "feedback": f"Failed to retrieve project INP file: {str(e)} | " + " | ".join(feedback_parts)
            }

        # 3. Parse INP File
        
        # Check Azimuth
        # Pattern: looks for "BUILD-PARAMETERS" then "AZIMUTH = 90" inside it, 
        # but INP format is hierarchical. 
        # Simple regex: Look for AZIMUTH = 90 in the whole file if unique, 
        # or find the BUILD-PARAMETERS block.
        # In eQUEST INP, AZIMUTH is usually under BUILD-PARAMETERS.
        
        azimuth_match = re.search(r'AZIMUTH\s*=\s*(\d+)', inp_content)
        if azimuth_match:
            azimuth_val = int(azimuth_match.group(1))
            if 89 <= azimuth_val <= 91:
                score += 20
                feedback_parts.append(f"Azimuth correct ({azimuth_val}) (+20)")
            else:
                feedback_parts.append(f"Azimuth incorrect (Found: {azimuth_val}, Expected: 90)")
        else:
            # If AZIMUTH is missing, it's 0 (default)
            feedback_parts.append("Azimuth parameter not found (Value is 0/Default)")

        # Check Ground Floor Systems
        # We need to find "SYSTEM" commands where Name starts with "G."
        # Structure: 
        # "G.S01" = SYSTEM
        #    TYPE             = PSZ
        #    HEAT-SOURCE      = FURNACE
        #    COOL-SET-T       = 58
        #    ...
        # ..
        
        # Regex to split into blocks or find systems
        # Find all blocks: "Name" = SYSTEM ... ..
        
        # Ground systems expected
        g_systems = ["G.S11", "G.E12", "G.N13", "G.W14", "G.C15"] # Based on known model structure or generalized regex
        # Since exact names might vary slightly in description vs reality, lets look for any system starting with "G."
        
        # Regex to find system blocks:
        # "Name" = SYSTEM ... (content) ... ..
        system_blocks = re.findall(r'"([^"]+)"\s*=\s*SYSTEM\s*(.*?)\.\.', inp_content, re.DOTALL)
        
        updated_systems = 0
        target_systems_found = 0
        
        for name, content in system_blocks:
            if name.startswith("G."):
                target_systems_found += 1
                # Check for COOL-SET-T
                cool_match = re.search(r'COOL-SET-T\s*=\s*([0-9.]+)', content)
                if cool_match:
                    val = float(cool_match.group(1))
                    if 57.5 <= val <= 58.5:
                        updated_systems += 1
                # If parameter missing, it's default (55)
        
        # Scoring for systems (max 60 pts)
        # If we found 5 systems, each is worth 12.
        # If we found different number, scale accordingly? 
        # Let's stick to the 5 known systems logic.
        
        if target_systems_found == 0:
            feedback_parts.append("No Ground Floor (G.*) systems found in INP file!")
        else:
            # Cap at 5 systems for scoring to match expected 4StoreyBuilding model
            count = min(updated_systems, 5) 
            pts = count * 12
            score += pts
            feedback_parts.append(f"Systems updated: {count}/{min(target_systems_found, 5)} (+{pts})")

    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
        if os.path.exists(temp_inp.name):
            os.unlink(temp_inp.name)

    passed = (score >= 60) and sim_ran
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }