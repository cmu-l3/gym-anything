#!/usr/bin/env python3
"""
Verifier for exterior_lighting_submeter_setup task.
Checks for correct creation of Schedule, Meter, and Exterior Lighting objects.
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_exterior_lighting_submeter_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Path inside container defined in export_result.ps1
        copy_from_env("C:\\Users\\Docker\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Check Simulation (10 pts)
    if result.get('sim_run', False):
        score += 10
        feedback.append("Simulation ran successfully (+10).")
    else:
        feedback.append("Simulation did not run or was stale.")

    # 2. Check Meter Creation (20 pts)
    meters = result.get('meters', [])
    target_meter_found = False
    for m in meters:
        if "ext" in m.lower() and "light" in m.lower() and "meter" in m.lower():
            target_meter_found = True
            score += 20
            feedback.append(f"Meter '{m}' created (+20).")
            break
    if not target_meter_found:
        feedback.append("No 'Ext Lighting Meter' found.")

    # 3. Check Schedule Logic (25 pts)
    # Requirement: ON (1.0) for hours 1-6 and 19-24. OFF (0.0) for 7-18.
    schedules = result.get('schedules', [])
    valid_sch_name = None
    
    for sch in schedules:
        vals_str = sch.get('values', '')
        # BDL values are space separated
        try:
            vals = [float(v) for v in vals_str.split()]
        except:
            continue
            
        if len(vals) != 24:
            continue
            
        # Check profile
        # Hours 0-5 (1-6 in 1-index) should be 1.0
        # Hours 6-17 (7-18 in 1-index) should be 0.0
        # Hours 18-23 (19-24 in 1-index) should be 1.0
        
        is_dusk_dawn = True
        for i in range(24):
            hour_idx = i + 1
            expected = 1.0 if (hour_idx <= 6 or hour_idx >= 19) else 0.0
            if abs(vals[i] - expected) > 0.1:
                is_dusk_dawn = False
                break
        
        if is_dusk_dawn:
            valid_sch_name = sch.get('name')
            score += 25
            feedback.append(f"Schedule '{valid_sch_name}' matches dusk-to-dawn profile (+25).")
            break
            
    if not valid_sch_name:
        feedback.append("No schedule found matching 7 PM - 6 AM profile.")

    # 4. Check Exterior Lighting Object (45 pts total)
    # Needs to exist, have power 4.5, and use the meter/schedule
    ext_lights = result.get('exterior_lights', [])
    
    valid_load_found = False
    for el in ext_lights:
        el_score = 0
        el_feedback = []
        
        # Check Power (10 pts)
        try:
            p = float(el.get('power', 0))
            if abs(p - 4.5) < 0.1:
                el_score += 10
                el_feedback.append("Power correct")
        except:
            pass
            
        # Check Meter Assignment (10 pts)
        m_assign = el.get('meter', '')
        if target_meter_found and m_assign and ("ext" in m_assign.lower()):
            el_score += 10
            el_feedback.append("Meter assigned")
            
        # Check Schedule Assignment (10 pts)
        s_assign = el.get('schedule', '')
        if valid_sch_name and s_assign == valid_sch_name:
            el_score += 10
            el_feedback.append("Schedule assigned")
            
        # Base existence (15 pts)
        if el_score > 0: # If it got any points, it exists and is somewhat correct
            el_score += 15
            score += el_score
            feedback.append(f"Load '{el.get('name')}' created: {', '.join(el_feedback)} (+{el_score}).")
            valid_load_found = True
            break
            
    if not valid_load_found:
        feedback.append("No valid Exterior Lighting load found.")

    passed = (score >= 60) and valid_load_found and target_meter_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }