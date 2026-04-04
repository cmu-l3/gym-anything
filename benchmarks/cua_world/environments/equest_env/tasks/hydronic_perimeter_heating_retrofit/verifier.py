#!/usr/bin/env python3
"""
Verifier for hydronic_perimeter_heating_retrofit task.
Evaluates if the agent correctly created the loop, boiler, and updated zone baseboards.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\hydronic_retrofit_result.json"

def verify_hydronic_retrofit(traj, env_info, task_info):
    """
    Verifies the eQUEST model update.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result from guest
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task result (task may not have completed successfully): {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Simulation Check (10 pts)
    if result.get('sim_ran', False):
        score += 10
        feedback.append("Simulation ran successfully (+10).")
    else:
        feedback.append("Simulation did not run during the task session.")

    # 2. Loop Verification (15 pts)
    # Check creation
    if result.get('loop_exists', False):
        score += 5
        feedback.append("Loop 'Perimeter_HW_Loop' created (+5).")
        
        # Check Temp (180)
        loop_temp = result.get('loop_temp', '')
        try:
            if loop_temp and abs(float(loop_temp) - 180.0) < 5:
                score += 10
                feedback.append("Loop temperature correct (+10).")
            else:
                feedback.append(f"Loop temperature incorrect: found {loop_temp}, expected 180.")
        except:
            feedback.append(f"Loop temperature invalid/missing: {loop_temp}")
    else:
        feedback.append("Loop 'Perimeter_HW_Loop' NOT found.")

    # 3. Boiler Verification (25 pts)
    if result.get('boiler_exists', False):
        score += 5
        feedback.append("Boiler 'Perimeter_Boiler' created (+5).")
        
        # Check Link to Loop
        boiler_loop = result.get('boiler_loop', '')
        if boiler_loop and 'Perimeter_HW_Loop' in boiler_loop.strip('"'):
            score += 10
            feedback.append("Boiler correctly linked to Loop (+10).")
        else:
            feedback.append(f"Boiler not linked to correct loop: found {boiler_loop}.")
            
        # Check HIR (1.04)
        boiler_hir = result.get('boiler_hir', '')
        try:
            if boiler_hir and abs(float(boiler_hir) - 1.04) < 0.02:
                score += 10
                feedback.append("Boiler HIR correct (+10).")
            else:
                feedback.append(f"Boiler HIR incorrect: found {boiler_hir}, expected 1.04.")
        except:
            feedback.append("Boiler HIR invalid.")
    else:
        feedback.append("Boiler 'Perimeter_Boiler' NOT found.")

    # 4. Zone Verification (50 pts - 12.5 per zone)
    zones = result.get('zones', {})
    target_zones = ["T.S31", "T.E32", "T.N33", "T.W34"]
    
    zones_correct_count = 0
    
    for z_name in target_zones:
        z_data = zones.get(z_name, {})
        z_score = 0
        z_pass = True
        
        # Check Source
        src = z_data.get('source', '')
        if src and 'HOT-WATER' in src.upper():
            z_score += 3
        else:
            z_pass = False
            
        # Check Loop Link
        z_loop = z_data.get('loop', '')
        if z_loop and 'Perimeter_HW_Loop' in z_loop.strip('"'):
            z_score += 3
        else:
            z_pass = False
            
        # Check Rating (15000 or -15000)
        rating = z_data.get('rating', '')
        try:
            val = float(rating)
            if abs(abs(val) - 15000) < 500:
                z_score += 4
            else:
                z_pass = False
        except:
            z_pass = False
            
        # Check Control
        ctrl = z_data.get('control', '')
        if ctrl and 'THERMOSTATIC' in ctrl.upper():
            z_score += 2.5
        else:
            z_pass = False
            
        score += z_score
        if z_pass:
            zones_correct_count += 1

    feedback.append(f"Zones fully correct: {zones_correct_count}/4.")

    # Final tally
    passed = (score >= 70) and result.get('sim_ran', False) and (result.get('loop_exists', False))
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }