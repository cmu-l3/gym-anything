#!/usr/bin/env python3
"""
Verifier for configure_orbital_docking_connectors task.

Validates that the agent correctly reconfigured the Connector nodes on both 
the Chaser and Target satellites to establish a valid active-passive latch 
with appropriate capture tolerances and infinite tensile strength.
"""

import json
import re
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

def is_close(a, b, rel_tol=1e-4):
    """Helper to safely compare floats."""
    return abs(a - b) <= rel_tol

def verify_configure_orbital_docking_connectors(traj, env_info, task_info):
    """
    Verifies the orbital docking parameters by parsing the saved Webots .wbt file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable - framework error."}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('expected_output_path', '/home/ga/Desktop/orbital_docking.wbt')
    
    # 1. Fetch the JSON export results
    result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_file.close()
    try:
        copy_from_env('/tmp/task_result.json', result_file.name)
        with open(result_file.name) as f:
            export_result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load export result: {e}")
        export_result = {}
    finally:
        if os.path.exists(result_file.name):
            os.unlink(result_file.name)
            
    # Anti-gaming check
    if not export_result.get("file_created_during_task", False) and export_result.get("output_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file existed before the task started. You must save the file during your session."
        }

    # 2. Fetch and read the saved Webots .wbt file
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_file.close()
    wbt_content = None
    try:
        copy_from_env(output_path, wbt_file.name)
        with open(wbt_file.name, 'r', errors='replace') as f:
            wbt_content = f.read()
    except Exception as e:
        logger.warning(f"Could not copy .wbt file: {e}")
    finally:
        if os.path.exists(wbt_file.name):
            os.unlink(wbt_file.name)

    score = 0
    feedback = []
    
    if not wbt_content or len(wbt_content) < 100:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"World file not found at {output_path} or is empty. Did you use File > Save World As?"
        }
        
    score += 10
    feedback.append("World file saved at correct path.")
    
    # Split the file by node definitions to isolate the two robots
    chaser_block = ""
    target_block = ""
    for block in wbt_content.split('DEF '):
        if block.startswith('CHASER_SATELLITE'):
            chaser_block = block
        elif block.startswith('TARGET_SATELLITE'):
            target_block = block
            
    if not chaser_block or not target_block:
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback) + " | Missing CHASER_SATELLITE or TARGET_SATELLITE definition in the saved world."
        }

    # Evaluate Chaser Properties
    ch_type_m = re.search(r'type\s+"([^"]+)"', chaser_block)
    ch_type = ch_type_m.group(1) if ch_type_m else "symmetric"
    
    if ch_type == "active":
        score += 20
        feedback.append("Chaser type correctly set to 'active'.")
    else:
        feedback.append(f"Chaser type is '{ch_type}', expected 'active'.")
        
    ch_tens_m = re.search(r'tensileStrength\s+([\d.-]+)', chaser_block)
    ch_tens = float(ch_tens_m.group(1)) if ch_tens_m else 0.0  
    
    if is_close(ch_tens, -1.0):
        score += 20
        feedback.append("Chaser tensileStrength correctly set to -1.")
    else:
        feedback.append(f"Chaser tensileStrength is {ch_tens}, expected -1.")
        
    ch_dist_m = re.search(r'distanceTolerance\s+([\d.-]+)', chaser_block)
    ch_dist = float(ch_dist_m.group(1)) if ch_dist_m else 0.01
    
    if is_close(ch_dist, 0.05):
        score += 25
        feedback.append("Chaser distanceTolerance correctly set to 0.05.")
    else:
        feedback.append(f"Chaser distanceTolerance is {ch_dist}, expected 0.05.")
        
    # Evaluate Target Properties
    tg_type_m = re.search(r'type\s+"([^"]+)"', target_block)
    tg_type = tg_type_m.group(1) if tg_type_m else "symmetric"
    if tg_type != "passive":
        feedback.append(f"WARNING: Target type was changed to '{tg_type}', it should have remained 'passive'.")

    tg_dist_m = re.search(r'distanceTolerance\s+([\d.-]+)', target_block)
    tg_dist = float(tg_dist_m.group(1)) if tg_dist_m else 0.01
    
    if is_close(tg_dist, 0.05):
        score += 25
        feedback.append("Target distanceTolerance correctly set to 0.05.")
    else:
        feedback.append(f"Target distanceTolerance is {tg_dist}, expected 0.05.")

    # Determine passing based on absolute strictness for the mechanistic connection
    passed = (score >= 75 and 
              ch_type == "active" and 
              is_close(tg_dist, 0.05) and 
              tg_type == "passive")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }