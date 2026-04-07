#!/usr/bin/env python3
"""
Verifier for Record Vital Signs task in OpenEMR.

MULTI-CRITERIA VERIFICATION:
1. Patient found (correct patient pid=3): 10 points
2. Encounter created: 15 points
3. Vitals form submitted: 15 points
4. Blood pressure correct (128/82 ±3): 15 points
5. Pulse correct (76 ±2): 10 points
6. Temperature correct (98.4 ±0.2): 10 points
7. Respiratory rate correct (16 ±1): 5 points
8. Oxygen saturation correct (98 ±1): 5 points
9. Weight correct (185 ±2): 8 points
10. Height correct (70 ±1): 7 points

Pass threshold: 70 points with "Vitals form submitted" criterion met

ANTI-GAMING:
- Vitals must be newly created (count increased during task)
- Timestamp validation via task_start/task_end
- Must be for correct patient (not any patient)
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def safe_float(value, default=None) -> Optional[float]:
    """Safely convert value to float, handling NULL and empty strings."""
    if value is None or value == "null" or value == "" or value == "NULL":
        return default
    try:
        return float(value)
    except (ValueError, TypeError):
        return default


def check_value_tolerance(actual, expected, tolerance, name: str) -> Dict[str, Any]:
    """Check if actual value is within tolerance of expected value."""
    result = {
        "name": name,
        "actual": actual,
        "expected": expected,
        "tolerance": tolerance,
        "within_tolerance": False,
        "difference": None
    }
    
    if actual is None:
        result["error"] = "Value not recorded"
        return result
    
    diff = abs(actual - expected)
    result["difference"] = diff
    result["within_tolerance"] = diff <= tolerance
    
    return result


def verify_record_vital_signs(traj, env_info, task_info):
    """
    Verify that vital signs were correctly recorded for the patient.
    
    Uses copy_from_env to read exported verification data (NOT exec_in_env).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 3)
    expected_bps = metadata.get('expected_bps', 128)
    expected_bpd = metadata.get('expected_bpd', 82)
    expected_pulse = metadata.get('expected_pulse', 76)
    expected_temp = metadata.get('expected_temperature', 98.4)
    expected_resp = metadata.get('expected_respiration', 16)
    expected_o2 = metadata.get('expected_oxygen_saturation', 98)
    expected_weight = metadata.get('expected_weight', 185)
    expected_height = metadata.get('expected_height', 70)
    
    # Tolerances
    bp_tol = metadata.get('bp_tolerance', 3)
    pulse_tol = metadata.get('pulse_tolerance', 2)
    temp_tol = metadata.get('temp_tolerance', 0.2)
    resp_tol = metadata.get('resp_tolerance', 1)
    o2_tol = metadata.get('o2_tolerance', 1)
    weight_tol = metadata.get('weight_tolerance', 2)
    height_tol = metadata.get('height_tolerance', 1)
    
    # Copy result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result file: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to read result file: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
    
    # Initialize scoring
    score = 0
    max_score = 100
    feedback_parts = []
    subscores = {
        "patient_found": False,
        "encounter_created": False,
        "vitals_submitted": False,
        "bp_correct": False,
        "pulse_correct": False,
        "temperature_correct": False,
        "respiration_correct": False,
        "oxygen_correct": False,
        "weight_correct": False,
        "height_correct": False
    }
    value_checks = []
    
    # Extract data from result
    patient_pid = result.get('patient_pid', 0)
    initial_vitals = result.get('initial_vitals_count', 0)
    current_vitals = result.get('current_vitals_count', 0)
    initial_encounters = result.get('initial_encounter_count', 0)
    current_encounters = result.get('current_encounter_count', 0)
    new_vitals_found = result.get('new_vitals_found', False)
    new_encounter_found = result.get('new_encounter_found', False)
    vitals = result.get('vitals', {})
    encounter = result.get('encounter', {})
    
    logger.info(f"Patient PID: {patient_pid}, Expected: {expected_pid}")
    logger.info(f"Vitals count: initial={initial_vitals}, current={current_vitals}")
    logger.info(f"Encounter count: initial={initial_encounters}, current={current_encounters}")
    logger.info(f"New vitals found: {new_vitals_found}")
    logger.info(f"Vitals data: {vitals}")
    
    # ================================================================
    # CRITERION 1: Correct patient (10 points)
    # ================================================================
    if patient_pid == expected_pid:
        score += 10
        subscores["patient_found"] = True
        feedback_parts.append(f"Correct patient (pid={expected_pid})")
    else:
        feedback_parts.append(f"CRITICAL: Wrong patient! Expected pid={expected_pid}, got {patient_pid}")
        # Wrong patient is a critical failure
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Vitals recorded for wrong patient (expected pid={expected_pid})",
            "subscores": subscores
        }
    
    # ================================================================
    # CRITERION 2: Encounter created (15 points)
    # ================================================================
    if new_encounter_found or current_encounters > initial_encounters:
        score += 15
        subscores["encounter_created"] = True
        encounter_reason = encounter.get('reason', 'unknown')
        feedback_parts.append(f"New encounter created (reason: {encounter_reason})")
    else:
        feedback_parts.append("No new encounter created")
    
    # ================================================================
    # CRITERION 3: Vitals form submitted (15 points)
    # ================================================================
    if new_vitals_found and current_vitals > initial_vitals:
        score += 15
        subscores["vitals_submitted"] = True
        feedback_parts.append(f"New vitals submitted (count: {initial_vitals} -> {current_vitals})")
    else:
        feedback_parts.append("No new vitals form submitted")
        # If no vitals submitted, return early with partial score
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "initial_vitals_count": initial_vitals,
                "current_vitals_count": current_vitals,
                "reason": "No new vital signs were recorded"
            }
        }
    
    # ================================================================
    # CRITERION 4: Blood Pressure correct (15 points)
    # ================================================================
    actual_bps = safe_float(vitals.get('bps'))
    actual_bpd = safe_float(vitals.get('bpd'))
    
    bps_check = check_value_tolerance(actual_bps, expected_bps, bp_tol, "Systolic BP")
    bpd_check = check_value_tolerance(actual_bpd, expected_bpd, bp_tol, "Diastolic BP")
    value_checks.extend([bps_check, bpd_check])
    
    if bps_check["within_tolerance"] and bpd_check["within_tolerance"]:
        score += 15
        subscores["bp_correct"] = True
        feedback_parts.append(f"BP correct: {actual_bps}/{actual_bpd} (expected {expected_bps}/{expected_bpd})")
    elif bps_check["within_tolerance"] or bpd_check["within_tolerance"]:
        score += 8  # Partial credit
        feedback_parts.append(f"BP partially correct: {actual_bps}/{actual_bpd}")
    else:
        if actual_bps is not None and actual_bpd is not None:
            feedback_parts.append(f"BP incorrect: {actual_bps}/{actual_bpd} (expected {expected_bps}/{expected_bpd})")
        else:
            feedback_parts.append("BP not recorded")
    
    # ================================================================
    # CRITERION 5: Pulse correct (10 points)
    # ================================================================
    actual_pulse = safe_float(vitals.get('pulse'))
    pulse_check = check_value_tolerance(actual_pulse, expected_pulse, pulse_tol, "Pulse")
    value_checks.append(pulse_check)
    
    if pulse_check["within_tolerance"]:
        score += 10
        subscores["pulse_correct"] = True
        feedback_parts.append(f"Pulse correct: {actual_pulse}")
    elif actual_pulse is not None:
        feedback_parts.append(f"Pulse incorrect: {actual_pulse} (expected {expected_pulse})")
    else:
        feedback_parts.append("Pulse not recorded")
    
    # ================================================================
    # CRITERION 6: Temperature correct (10 points)
    # ================================================================
    actual_temp = safe_float(vitals.get('temperature'))
    temp_check = check_value_tolerance(actual_temp, expected_temp, temp_tol, "Temperature")
    value_checks.append(temp_check)
    
    if temp_check["within_tolerance"]:
        score += 10
        subscores["temperature_correct"] = True
        feedback_parts.append(f"Temperature correct: {actual_temp}")
    elif actual_temp is not None:
        feedback_parts.append(f"Temperature incorrect: {actual_temp} (expected {expected_temp})")
    else:
        feedback_parts.append("Temperature not recorded")
    
    # ================================================================
    # CRITERION 7: Respiratory rate correct (5 points)
    # ================================================================
    actual_resp = safe_float(vitals.get('respiration'))
    resp_check = check_value_tolerance(actual_resp, expected_resp, resp_tol, "Respiration")
    value_checks.append(resp_check)
    
    if resp_check["within_tolerance"]:
        score += 5
        subscores["respiration_correct"] = True
        feedback_parts.append(f"Respiration correct: {actual_resp}")
    elif actual_resp is not None:
        feedback_parts.append(f"Respiration incorrect: {actual_resp} (expected {expected_resp})")
    else:
        feedback_parts.append("Respiration not recorded")
    
    # ================================================================
    # CRITERION 8: Oxygen saturation correct (5 points)
    # ================================================================
    actual_o2 = safe_float(vitals.get('oxygen_saturation'))
    o2_check = check_value_tolerance(actual_o2, expected_o2, o2_tol, "O2 Saturation")
    value_checks.append(o2_check)
    
    if o2_check["within_tolerance"]:
        score += 5
        subscores["oxygen_correct"] = True
        feedback_parts.append(f"O2 saturation correct: {actual_o2}")
    elif actual_o2 is not None:
        feedback_parts.append(f"O2 saturation incorrect: {actual_o2} (expected {expected_o2})")
    else:
        feedback_parts.append("O2 saturation not recorded")
    
    # ================================================================
    # CRITERION 9: Weight correct (8 points)
    # ================================================================
    actual_weight = safe_float(vitals.get('weight'))
    weight_check = check_value_tolerance(actual_weight, expected_weight, weight_tol, "Weight")
    value_checks.append(weight_check)
    
    if weight_check["within_tolerance"]:
        score += 8
        subscores["weight_correct"] = True
        feedback_parts.append(f"Weight correct: {actual_weight}")
    elif actual_weight is not None:
        feedback_parts.append(f"Weight incorrect: {actual_weight} (expected {expected_weight})")
    else:
        feedback_parts.append("Weight not recorded")
    
    # ================================================================
    # CRITERION 10: Height correct (7 points)
    # ================================================================
    actual_height = safe_float(vitals.get('height'))
    height_check = check_value_tolerance(actual_height, expected_height, height_tol, "Height")
    value_checks.append(height_check)
    
    if height_check["within_tolerance"]:
        score += 7
        subscores["height_correct"] = True
        feedback_parts.append(f"Height correct: {actual_height}")
    elif actual_height is not None:
        feedback_parts.append(f"Height incorrect: {actual_height} (expected {expected_height})")
    else:
        feedback_parts.append("Height not recorded")
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    # Pass requires: 70+ points AND vitals form was submitted
    key_criteria_met = subscores["vitals_submitted"]
    passed = score >= 70 and key_criteria_met
    
    # Generate summary
    correct_values = sum([
        subscores["bp_correct"],
        subscores["pulse_correct"],
        subscores["temperature_correct"],
        subscores["respiration_correct"],
        subscores["oxygen_correct"],
        subscores["weight_correct"],
        subscores["height_correct"]
    ])
    
    summary = f"Score: {score}/{max_score} | {correct_values}/7 vital signs correct"
    if passed:
        summary += " | PASSED"
    else:
        if not key_criteria_met:
            summary += " | FAILED: Vitals not submitted"
        else:
            summary += " | FAILED: Score below threshold"
    
    logger.info(summary)
    logger.info(f"Subscores: {subscores}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": summary + " | " + " | ".join(feedback_parts[:5]),  # Limit feedback length
        "subscores": subscores,
        "details": {
            "value_checks": value_checks,
            "vitals_recorded": {
                "bps": actual_bps,
                "bpd": actual_bpd,
                "pulse": actual_pulse,
                "temperature": actual_temp,
                "respiration": actual_resp,
                "oxygen_saturation": actual_o2,
                "weight": actual_weight,
                "height": actual_height
            },
            "expected_values": {
                "bps": expected_bps,
                "bpd": expected_bpd,
                "pulse": expected_pulse,
                "temperature": expected_temp,
                "respiration": expected_resp,
                "oxygen_saturation": expected_o2,
                "weight": expected_weight,
                "height": expected_height
            },
            "encounter_created": subscores["encounter_created"],
            "initial_vitals_count": initial_vitals,
            "final_vitals_count": current_vitals
        }
    }