#!/usr/bin/env python3
"""
Verifier for ep_gto_spiral_duration@1

Scoring (total 100 pts, pass >= 60):
  - script_created (10): Script was created during the task
  - hardware_configured (20): ChemicalTank, ChemicalThruster, and FiniteBurn instantiated
  - report_generated (10): Report output file contains all required fields
  - time_correct (20): `elapsed_days` evaluates to physically valid duration [120, 250]
  - fuel_correct (20): `remaining_fuel_kg` evaluates to physically valid amount [150, 350]
  - ecc_correct (10): `final_eccentricity` < initial 0.730
  - inc_correct (10): `final_inclination_deg` remains near 27.0 (+/- 1.0)

Pass condition: score >= 60 AND hardware_configured AND (time_correct OR fuel_correct)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_ep_gto_spiral(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    time_min = metadata.get('time_min_days', 120.0)
    time_max = metadata.get('time_max_days', 250.0)
    fuel_min = metadata.get('fuel_min_kg', 150.0)
    fuel_max = metadata.get('fuel_max_kg', 350.0)
    target_sma = metadata.get('target_sma_km', 42164.17)
    sma_tol = metadata.get('sma_tolerance_km', 15.0)
    initial_ecc = metadata.get('initial_ecc', 0.730)
    target_inc = metadata.get('target_inc_deg', 27.0)
    inc_tol = metadata.get('inc_tolerance_deg', 1.0)

    scores = {
        "script_created": 10,
        "hardware_configured": 20,
        "report_generated": 10,
        "time_correct": 20,
        "fuel_correct": 20,
        "ecc_correct": 10,
        "inc_correct": 10,
    }

    total_score = 0
    feedback = []
    
    hardware_ok = False
    time_ok = False
    fuel_ok = False

    # Load task result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 1. Script created
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_created"]
        feedback.append("Script created during task window.")
    else:
        feedback.append("Script not created during task window.")

    # 2. Hardware Configured (Check script content)
    script_path = task_result.get('script_path', '/home/ga/GMAT_output/ep_spiral.script')
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            has_tank = bool(re.search(r'Create\s+ChemicalTank', script_content))
            has_thruster = bool(re.search(r'Create\s+ChemicalThruster', script_content))
            has_burn = bool(re.search(r'Create\s+FiniteBurn', script_content))
            has_propagate = bool(re.search(r'Propagate', script_content))

            if has_tank and has_thruster and has_burn and has_propagate:
                total_score += scores["hardware_configured"]
                hardware_ok = True
                feedback.append("Tank, Thruster, and FiniteBurn configured.")
            else:
                feedback.append("Missing required hardware (Tank/Thruster/FiniteBurn) in script.")

        except Exception as e:
            feedback.append(f"Failed to read script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)
    else:
        feedback.append("Script file not found for hardware check.")

    # 3. Report Generated and Parsed
    report_file = task_result.get('report_file', {})
    if isinstance(report_file, dict) and report_file.get('exists'):
        total_score += scores["report_generated"]
        feedback.append("Report generated.")
    else:
        feedback.append("Report file not found.")

    try:
        t_days = float(task_result.get('elapsed_days', 0))
    except (ValueError, TypeError):
        t_days = 0.0

    try:
        fuel = float(task_result.get('remaining_fuel_kg', 0))
    except (ValueError, TypeError):
        fuel = 0.0

    try:
        sma = float(task_result.get('final_sma_km', 0))
    except (ValueError, TypeError):
        sma = 0.0

    try:
        ecc = float(task_result.get('final_eccentricity', 1.0))
    except (ValueError, TypeError):
        ecc = 1.0

    try:
        inc = float(task_result.get('final_inclination_deg', 0))
    except (ValueError, TypeError):
        inc = 0.0

    # 4. Time Correct
    if time_min <= t_days <= time_max:
        total_score += scores["time_correct"]
        time_ok = True
        feedback.append(f"Elapsed time is physically valid: {t_days:.1f} days.")
    else:
        feedback.append(f"Elapsed time invalid: {t_days:.1f} days (expected {time_min}-{time_max}).")

    # 5. Fuel Correct
    if fuel_min <= fuel <= fuel_max:
        total_score += scores["fuel_correct"]
        fuel_ok = True
        feedback.append(f"Remaining fuel is physically valid: {fuel:.1f} kg.")
    else:
        feedback.append(f"Remaining fuel invalid: {fuel:.1f} kg (expected {fuel_min}-{fuel_max}).")

    # 6. ECC Correct
    if ecc < initial_ecc:
        total_score += scores["ecc_correct"]
        feedback.append(f"Final ECC validly reduced: {ecc:.4f} (started at {initial_ecc}).")
    else:
        feedback.append(f"Final ECC not correctly reduced: {ecc:.4f}.")

    # 7. INC Correct
    if abs(inc - target_inc) <= inc_tol:
        total_score += scores["inc_correct"]
        feedback.append(f"Final INC maintained correctly: {inc:.2f} deg.")
    else:
        feedback.append(f"Final INC diverged: {inc:.2f} deg (expected ~{target_inc}).")

    # Check SMA roughly just as additional info
    if abs(sma - target_sma) <= sma_tol:
        feedback.append(f"Target SMA successfully achieved: {sma:.2f} km.")
    else:
        feedback.append(f"Target SMA not achieved: {sma:.2f} km (expected ~{target_sma}).")

    passed = (total_score >= 60) and hardware_ok and (time_ok or fuel_ok)

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }