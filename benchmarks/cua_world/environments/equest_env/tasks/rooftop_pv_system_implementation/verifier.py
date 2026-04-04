#!/usr/bin/env python3
"""
Verifier for Rooftop PV System Implementation task.

Requirements:
1. Create PV Generator (ELEC-GENERATOR).
2. Capacity = 25.0 kW.
3. Tilt = 20 deg.
4. Azimuth = 180 deg.
5. Efficiency = 0.18.
6. Run Simulation (fresh .SIM file).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rooftop_pv_system_implementation(traj, env_info, task_info):
    """
    Verifies that the PV system was correctly implemented and simulated.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define targets
    metadata = task_info.get('metadata', {})
    TARGET_CAPACITY = metadata.get('target_capacity', 25.0)
    TARGET_TILT = metadata.get('target_tilt', 20.0)
    TARGET_AZIMUTH = metadata.get('target_azimuth', 180.0)
    TARGET_EFF = metadata.get('target_efficiency', 0.18)
    
    # Tolerances
    TOL_CAPACITY = 0.5
    TOL_TILT = 2.0
    TOL_AZIMUTH = 5.0
    TOL_EFF = 0.01

    score = 0
    feedback_parts = []
    
    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Container path is Windows style, but copy_from_env handles the abstraction usually.
        # If strict paths needed, we assume the one written by export_result.ps1
        copy_from_env("C:\\Users\\Docker\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 1. Check Simulation (20 pts)
    if result.get('sim_is_new', False):
        score += 20
        feedback_parts.append("Simulation ran successfully (+20)")
    else:
        feedback_parts.append("Simulation not run or results outdated")

    # 2. Check PV Object Existence (20 pts)
    if result.get('pv_exists', False):
        score += 20
        feedback_parts.append("PV Generator created (+20)")
    else:
        feedback_parts.append("No PV Generator found in model")
        return {"passed": False, "score": score, "feedback": "; ".join(feedback_parts)}

    # 3. Check Capacity (20 pts)
    cap = result.get('pv_capacity', 0)
    if abs(cap - TARGET_CAPACITY) <= TOL_CAPACITY:
        score += 20
        feedback_parts.append(f"Capacity correct ({cap} kW) (+20)")
    else:
        feedback_parts.append(f"Capacity mismatch: found {cap} kW, expected {TARGET_CAPACITY}")

    # 4. Check Geometry (Tilt/Azimuth) (20 pts)
    tilt = result.get('pv_tilt', 0)
    azimuth = result.get('pv_azimuth', 0)
    geo_pass = True
    
    if abs(tilt - TARGET_TILT) > TOL_TILT:
        geo_pass = False
        feedback_parts.append(f"Tilt mismatch: found {tilt}, expected {TARGET_TILT}")
    
    if abs(azimuth - TARGET_AZIMUTH) > TOL_AZIMUTH:
        geo_pass = False
        feedback_parts.append(f"Azimuth mismatch: found {azimuth}, expected {TARGET_AZIMUTH}")
        
    if geo_pass:
        score += 20
        feedback_parts.append("Geometry (Tilt/Azimuth) correct (+20)")

    # 5. Check Efficiency (20 pts)
    eff = result.get('pv_efficiency', 0)
    if abs(eff - TARGET_EFF) <= TOL_EFF:
        score += 20
        feedback_parts.append(f"Efficiency correct ({eff}) (+20)")
    else:
        feedback_parts.append(f"Efficiency mismatch: found {eff}, expected {TARGET_EFF}")

    # Final Pass Check
    # Must have run simulation AND got capacity right to pass
    passed = (score >= 80) and result.get('sim_is_new', False) and (abs(cap - TARGET_CAPACITY) <= TOL_CAPACITY)

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }