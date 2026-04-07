#!/usr/bin/env python3
"""
Verifier for gps_graveyard_disposal@1

Scoring (total 100 pts, pass >= 60):
  - script_created (10): Script created during task window
  - spacecraft_defined (10): Script defines spacecraft
  - initial_orbit_correct (10): Script contains correct initial SMA/ECC/INC
  - two_burns_present (15): Two impulsive or finite burns defined
  - propagation_logic (5): Multiple propagates present (transfer + stability)
  - report_written (10): Disposal report written with required fields
  - final_sma_valid (15): Final SMA > 27059.7 km (minimum 500 km raise)
  - final_ecc_valid (5): Final ECC < 0.01
  - deltav_valid (10): Total Delta-V in [20, 100] m/s
  - fuel_valid (5): Fuel consumed in [10, 52] kg
  - compliance_stated (5): Report correctly identifies COMPLIANT

Pass condition: score >= 60 AND final_sma_valid AND two_burns_present
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def safe_float(val, default=0.0):
    try:
        return float(val)
    except (ValueError, TypeError):
        return default

def verify_gps_graveyard_disposal(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    min_final_sma = metadata.get('min_final_sma_km', 27059.7)
    max_ecc = metadata.get('max_final_ecc', 0.01)
    min_dv = metadata.get('min_deltav_mps', 20.0)
    max_dv = metadata.get('max_deltav_mps', 100.0)
    min_fuel = metadata.get('min_fuel_kg', 10.0)
    max_fuel = metadata.get('max_fuel_kg', 52.0)

    scores = {
        "script_created": 10,
        "spacecraft_defined": 10,
        "initial_orbit_correct": 10,
        "two_burns_present": 15,
        "propagation_logic": 5,
        "report_written": 10,
        "final_sma_valid": 15,
        "final_ecc_valid": 5,
        "deltav_valid": 10,
        "fuel_valid": 5,
        "compliance_stated": 5,
    }

    total_score = 0
    feedback = []
    
    sma_ok = False
    burns_ok = False

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

    # 1. Check script modifications
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_created"]
        feedback.append("Script created during task window.")
    else:
        feedback.append("Script not created or modified during task window.")

    # 2. Check script contents
    if task_result.get('sc_defined', False):
        total_score += scores["spacecraft_defined"]
        feedback.append("Spacecraft definition found.")
        
    if task_result.get('init_orbit_correct', False):
        total_score += scores["initial_orbit_correct"]
        feedback.append("Initial orbital parameters correct (SMA, INC, ECC).")
        
    if task_result.get('two_burns_present', False):
        total_score += scores["two_burns_present"]
        burns_ok = True
        feedback.append("Two Hohmann burns present in script.")
    else:
        feedback.append("Failed to detect two burns in script.")
        
    if task_result.get('propagation_logic', False):
        total_score += scores["propagation_logic"]
        feedback.append("Sufficient propagation logic found.")

    # 3. Check report file
    report_file = task_result.get('report_file', {})
    if isinstance(report_file, dict) and report_file.get('created_during_task'):
        
        # Count non-zero required fields
        reported_fin_sma = safe_float(task_result.get('reported_fin_sma'))
        reported_tot_dv = safe_float(task_result.get('reported_tot_dv'))
        reported_fuel = safe_float(task_result.get('reported_fuel'))
        reported_fin_ecc = safe_float(task_result.get('reported_fin_ecc'))
        reported_comp = task_result.get('reported_compliance', '').upper()
        
        if reported_fin_sma > 0:
            total_score += scores["report_written"]
            feedback.append("Report successfully written and parsed.")
            
            # Check values
            if reported_fin_sma >= min_final_sma:
                total_score += scores["final_sma_valid"]
                sma_ok = True
                feedback.append(f"Graveyard SMA is valid: {reported_fin_sma} km.")
            else:
                feedback.append(f"Graveyard SMA invalid: {reported_fin_sma} km (requires >= {min_final_sma}).")
                
            if reported_fin_ecc <= max_ecc:
                total_score += scores["final_ecc_valid"]
                feedback.append(f"Graveyard ECC is valid: {reported_fin_ecc}.")
            else:
                feedback.append(f"Graveyard ECC too high: {reported_fin_ecc}.")
                
            if min_dv <= reported_tot_dv <= max_dv:
                total_score += scores["deltav_valid"]
                feedback.append(f"Total Delta-V is realistic: {reported_tot_dv} m/s.")
            else:
                feedback.append(f"Total Delta-V out of expected range: {reported_tot_dv} m/s.")
                
            if min_fuel <= reported_fuel <= max_fuel:
                total_score += scores["fuel_valid"]
                feedback.append(f"Fuel consumption within budget: {reported_fuel} kg.")
            else:
                feedback.append(f"Fuel consumption out of budget or invalid: {reported_fuel} kg.")
                
            if reported_comp == "COMPLIANT":
                total_score += scores["compliance_stated"]
                feedback.append("Report explicitly states COMPLIANT.")
            else:
                feedback.append(f"Compliance state wrong or missing: {reported_comp}.")
        else:
            feedback.append("Report parsed but required fields missing or 0.")
    else:
        feedback.append("Report file not generated or not created during task window.")

    # Determine passing status
    passed = (total_score >= 60) and sma_ok and burns_ok

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback),
        "details": {
            "score_breakdown": {
                "script_created": scores["script_created"] if isinstance(script_file, dict) and script_file.get('created_during_task') else 0,
                "burns_ok": burns_ok,
                "sma_ok": sma_ok
            }
        }
    }