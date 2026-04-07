#!/usr/bin/env python3
"""
Verifier for mars_orbit_capture_and_science_acquisition@1

Scoring (total 100 pts, pass >= 65):
  - script_created (5):       Script file created during task window
  - mars_cs (5):              Mars-centered coordinate system configured
  - mars_gravity (10):        Mars50c gravity model with degree >= 10
  - sun_perturbation (5):     Sun third-body perturbation enabled
  - tank_configured (5):      ChemicalTank defined for fuel tracking
  - two_burns (5):            At least two ImpulsiveBurn objects defined
  - dc_targeting (10):        DifferentialCorrector with Target/Vary/Achieve
  - two_var_moi (5):          MOI targeting uses 2 Vary commands (combined burn)
  - results_file (5):         Results file written during task window
  - moi_deltav (8):           MOI delta-V in expected range
  - prm_deltav (7):           PRM delta-V in expected range
  - final_sma (8):            Post-PRM SMA matches science orbit target
  - final_ecc (5):            Post-PRM eccentricity matches target
  - final_inc (5):            Post-PRM inclination matches target (90 deg polar)
  - remaining_fuel (5):       Remaining fuel > 50 kg
  - stability (6):            Stability check reported (PASS or FAIL)

Pass condition: score >= 65 AND dc_targeting AND (moi_deltav OR final_sma)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_mars_orbit_capture(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})

    # Expected values from metadata
    moi_dv_exp = metadata.get('moi_expected_deltav_mps', 962.0)
    moi_dv_tol = metadata.get('moi_deltav_tolerance_mps', 100.0)
    moi_sma_target = metadata.get('moi_target_sma_km', 18546.0)
    moi_sma_tol = metadata.get('moi_sma_tolerance_km', 1000.0)
    moi_inc_target = metadata.get('moi_target_inc_deg', 90.0)
    moi_inc_tol = metadata.get('moi_inc_tolerance_deg', 2.0)
    moi_ecc_exp = metadata.get('moi_expected_ecc', 0.8007)
    moi_ecc_tol = metadata.get('moi_ecc_tolerance', 0.05)

    prm_dv_exp = metadata.get('prm_expected_deltav_mps', 306.0)
    prm_dv_tol = metadata.get('prm_deltav_tolerance_mps', 80.0)
    prm_sma_target = metadata.get('prm_target_sma_km', 8546.0)
    prm_sma_tol = metadata.get('prm_sma_tolerance_km', 500.0)
    prm_ecc_exp = metadata.get('prm_expected_ecc', 0.5676)
    prm_ecc_tol = metadata.get('prm_ecc_tolerance', 0.05)
    prm_inc_target = metadata.get('prm_target_inc_deg', 90.0)
    prm_inc_tol = metadata.get('prm_inc_tolerance_deg', 2.0)

    min_remaining_fuel = metadata.get('min_remaining_fuel_kg', 50.0)

    total_score = 0
    feedback = []
    dc_ok = False
    moi_dv_ok = False
    final_sma_ok = False

    # 1. Load exported result JSON
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

    def safe_float(val, default=0.0):
        try:
            return float(val)
        except (ValueError, TypeError):
            return default

    # 2. Script structure checks
    script_file = task_result.get('script_file', {})
    if script_file.get('exists') and script_file.get('created_during_task'):
        total_score += 5
        feedback.append("Script created during task window.")
    else:
        feedback.append("Script not created during task window or missing.")

    if task_result.get('mars_coordinate_system'):
        total_score += 5
        feedback.append("Mars-centered coordinate system found.")
    else:
        feedback.append("Missing Mars coordinate system (Origin = Mars).")

    if task_result.get('mars_gravity_model'):
        total_score += 10
        feedback.append("Mars50c gravity model configured.")
    else:
        feedback.append("Missing Mars50c gravity model.")

    if task_result.get('sun_perturbation'):
        total_score += 5
        feedback.append("Sun third-body perturbation enabled.")
    else:
        feedback.append("Missing Sun point-mass perturbation.")

    if task_result.get('tank_configured'):
        total_score += 5
        feedback.append("ChemicalTank configured for fuel tracking.")
    else:
        feedback.append("Missing ChemicalTank definition.")

    if task_result.get('two_burns_defined'):
        total_score += 5
        feedback.append("Two ImpulsiveBurn objects defined.")
    else:
        feedback.append("Less than two ImpulsiveBurn objects found.")

    if task_result.get('dc_targeting'):
        total_score += 10
        dc_ok = True
        feedback.append("DifferentialCorrector targeting logic found.")
    else:
        feedback.append("Missing DifferentialCorrector / Target / Vary / Achieve.")

    if task_result.get('two_variable_moi'):
        total_score += 5
        feedback.append("MOI targeting uses 2 Vary commands (combined capture + plane change).")
    else:
        feedback.append("MOI targeting does not use 2 Vary commands.")

    # 3. Results file checks
    results_file = task_result.get('results_file', {})
    if results_file.get('exists') and results_file.get('created_during_task'):
        total_score += 5
        feedback.append("Results file written during task window.")
    else:
        feedback.append("Results file not created or missing.")

    # 4. Numerical value checks
    moi_dv = safe_float(task_result.get('moi_deltav_mps'))
    # Handle km/s vs m/s: if value looks like km/s, convert
    if 0.1 < moi_dv < 10.0:
        moi_dv *= 1000.0

    if abs(moi_dv - moi_dv_exp) <= moi_dv_tol:
        total_score += 8
        moi_dv_ok = True
        feedback.append(f"MOI delta-V correct: {moi_dv:.1f} m/s (expected ~{moi_dv_exp:.0f}).")
    else:
        feedback.append(f"MOI delta-V out of range: {moi_dv:.1f} m/s (expected ~{moi_dv_exp:.0f} +/- {moi_dv_tol:.0f}).")

    prm_dv = safe_float(task_result.get('prm_deltav_mps'))
    if 0.1 < prm_dv < 10.0:
        prm_dv *= 1000.0

    if abs(prm_dv - prm_dv_exp) <= prm_dv_tol:
        total_score += 7
        feedback.append(f"PRM delta-V correct: {prm_dv:.1f} m/s (expected ~{prm_dv_exp:.0f}).")
    else:
        feedback.append(f"PRM delta-V out of range: {prm_dv:.1f} m/s (expected ~{prm_dv_exp:.0f} +/- {prm_dv_tol:.0f}).")

    prm_sma = safe_float(task_result.get('prm_postburn_sma_km'))
    if abs(prm_sma - prm_sma_target) <= prm_sma_tol:
        total_score += 8
        final_sma_ok = True
        feedback.append(f"Final science orbit SMA correct: {prm_sma:.1f} km (target {prm_sma_target:.0f}).")
    else:
        feedback.append(f"Final SMA out of range: {prm_sma:.1f} km (target {prm_sma_target:.0f} +/- {prm_sma_tol:.0f}).")

    prm_ecc = safe_float(task_result.get('prm_postburn_ecc'))
    if abs(prm_ecc - prm_ecc_exp) <= prm_ecc_tol:
        total_score += 5
        feedback.append(f"Final eccentricity correct: {prm_ecc:.4f}.")
    else:
        feedback.append(f"Final eccentricity out of range: {prm_ecc:.4f} (expected ~{prm_ecc_exp:.4f}).")

    prm_inc = safe_float(task_result.get('prm_postburn_inc_deg'))
    if abs(prm_inc - prm_inc_target) <= prm_inc_tol:
        total_score += 5
        feedback.append(f"Final inclination correct: {prm_inc:.2f} deg (target {prm_inc_target:.0f}).")
    else:
        feedback.append(f"Final inclination out of range: {prm_inc:.2f} deg (target {prm_inc_target:.0f} +/- {prm_inc_tol:.0f}).")

    remaining_fuel = safe_float(task_result.get('remaining_fuel_kg'))
    if remaining_fuel > min_remaining_fuel:
        total_score += 5
        feedback.append(f"Remaining fuel adequate: {remaining_fuel:.1f} kg.")
    else:
        feedback.append(f"Remaining fuel too low or missing: {remaining_fuel:.1f} kg (need > {min_remaining_fuel:.0f}).")

    stability = task_result.get('stability_30day', 'UNKNOWN')
    if stability in ('PASS', 'FAIL'):
        total_score += 6
        feedback.append(f"Stability assessment reported: {stability}.")
    else:
        feedback.append("Stability assessment not reported.")

    # 5. Final determination
    key_criteria = dc_ok and (moi_dv_ok or final_sma_ok)
    passed = total_score >= 65 and key_criteria

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback),
        "details": {
            "moi_deltav_mps": moi_dv,
            "prm_deltav_mps": prm_dv,
            "prm_sma_km": prm_sma,
            "prm_ecc": prm_ecc,
            "prm_inc_deg": prm_inc,
            "remaining_fuel_kg": remaining_fuel,
            "stability": stability,
            "dc_ok": dc_ok,
            "moi_dv_ok": moi_dv_ok,
            "final_sma_ok": final_sma_ok
        }
    }
