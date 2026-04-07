#!/usr/bin/env python3
"""
Verifier for record_patient_rounding task in GNU Health.

Evaluates the agent's ability to create a Patient Rounding record accurately
with all prescribed vital signs and Glasgow Coma Scale indicators.

Scoring breakdown (100 points total):
  - 15 pts: Rounding record exists for Ana created after task start
  - 12 pts: Temperature 37.8 (± 0.5)
  - 14 pts: Blood pressure 148/92 (± 5 each)
  - 12 pts: Heart rate 104 (± 5)
  - 10 pts: Respiratory rate 20 (± 2)
  - 10 pts: Oxygen saturation 96 (± 2)
  - 12 pts: Glycemia 285 (± 15)
  - 15 pts: GCS Eyes=4, Verbal=5, Motor=6 (Exact match required)

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def safe_float(val, default=None):
    if val is None or val == "null" or val == "":
        return default
    try:
        return float(val)
    except (ValueError, TypeError):
        return default


def verify_record_patient_rounding(traj, env_info, task_info):
    """Verify Patient Rounding record for inpatient Ana Isabel Betz."""
    copy_from_env = env_info.get('copy_from_env')
    metadata = task_info.get('metadata', {})
    expected = metadata.get('expected_vitals', {})

    score = 0
    feedback_parts = []
    subscores = {}

    # --- Copy result JSON from VM ---
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/record_patient_rounding_result.json', local_path)
        with open(local_path) as f:
            result = json.load(f)
        os.unlink(local_path)
    except Exception as e:
        logger.error(f"Failed to retrieve result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result file from VM: {e}",
            "subscores": {}
        }

    # --- CRITICAL CHECK: Correct patient ---
    target_id = result.get('target_patient_id', 0)
    if not target_id or target_id == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "CRITICAL: Patient Ana Isabel Betz not found — setup may have failed.",
            "subscores": {}
        }

    # --- Criterion 1: Rounding record exists (15 pts) ---
    record_found = result.get('record_found', False)
    any_new_record = result.get('any_new_record_count', 0)

    if record_found:
        score += 15
        subscores['record_exists'] = 15
        feedback_parts.append("Rounding record successfully created for Ana Isabel Betz")
    else:
        subscores['record_exists'] = 0
        if any_new_record > 0:
            feedback_parts.append(f"FAIL: {any_new_record} rounding records created, but NONE linked to Ana Isabel Betz's inpatient registration")
        else:
            feedback_parts.append("FAIL: No new Patient Rounding records were created")
        
        # If no record is found, they get 0 points overall
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    vitals = result.get('vitals', {})

    # --- Criterion 2: Temperature (12 pts) ---
    temp = safe_float(vitals.get('temperature'))
    exp_temp = expected.get('temperature', 37.8)
    if temp is not None and abs(temp - exp_temp) <= 0.5:
        score += 12
        subscores['temperature'] = 12
        feedback_parts.append(f"Temperature correct: {temp}C")
    else:
        subscores['temperature'] = 0
        feedback_parts.append(f"Temperature incorrect or missing (Expected ~{exp_temp}, Got {temp})")

    # --- Criterion 3: Blood Pressure (14 pts) ---
    sys = safe_float(vitals.get('systolic'))
    dia = safe_float(vitals.get('diastolic'))
    exp_sys = expected.get('systolic', 148)
    exp_dia = expected.get('diastolic', 92)
    
    bp_score = 0
    if sys is not None and abs(sys - exp_sys) <= 5:
        bp_score += 7
    if dia is not None and abs(dia - exp_dia) <= 5:
        bp_score += 7
        
    score += bp_score
    subscores['blood_pressure'] = bp_score
    if bp_score == 14:
        feedback_parts.append(f"Blood pressure correct: {sys}/{dia}")
    elif bp_score > 0:
        feedback_parts.append(f"Blood pressure partially correct: {sys}/{dia}")
    else:
        feedback_parts.append(f"Blood pressure incorrect or missing (Expected ~{exp_sys}/{exp_dia}, Got {sys}/{dia})")

    # --- Criterion 4: Heart Rate (12 pts) ---
    bpm = safe_float(vitals.get('bpm'))
    exp_bpm = expected.get('bpm', 104)
    if bpm is not None and abs(bpm - exp_bpm) <= 5:
        score += 12
        subscores['heart_rate'] = 12
        feedback_parts.append(f"Heart rate correct: {bpm} bpm")
    else:
        subscores['heart_rate'] = 0
        feedback_parts.append(f"Heart rate incorrect or missing (Expected ~{exp_bpm}, Got {bpm})")

    # --- Criterion 5: Respiratory Rate (10 pts) ---
    rr = safe_float(vitals.get('respiratory_rate'))
    exp_rr = expected.get('respiratory_rate', 20)
    if rr is not None and abs(rr - exp_rr) <= 2:
        score += 10
        subscores['respiratory_rate'] = 10
        feedback_parts.append(f"Respiratory rate correct: {rr} rpm")
    else:
        subscores['respiratory_rate'] = 0
        feedback_parts.append(f"Respiratory rate incorrect or missing (Expected ~{exp_rr}, Got {rr})")

    # --- Criterion 6: Oxygen Saturation (10 pts) ---
    osat = safe_float(vitals.get('osat'))
    exp_osat = expected.get('osat', 96)
    if osat is not None and abs(osat - exp_osat) <= 2:
        score += 10
        subscores['oxygen_saturation'] = 10
        feedback_parts.append(f"Oxygen saturation correct: {osat}%")
    else:
        subscores['oxygen_saturation'] = 0
        feedback_parts.append(f"Oxygen saturation incorrect or missing (Expected ~{exp_osat}, Got {osat})")

    # --- Criterion 7: Glycemia / Blood Glucose (12 pts) ---
    gly = safe_float(vitals.get('glycemia'))
    exp_gly = expected.get('glycemia', 285)
    if gly is not None and abs(gly - exp_gly) <= 15:
        score += 12
        subscores['glycemia'] = 12
        feedback_parts.append(f"Glycemia correct: {gly} mg/dL")
    else:
        subscores['glycemia'] = 0
        feedback_parts.append(f"Glycemia incorrect or missing (Expected ~{exp_gly}, Got {gly})")

    # --- Criterion 8: Glasgow Coma Scale (15 pts) ---
    gcs_e = safe_float(vitals.get('gcs_eyes'))
    gcs_v = safe_float(vitals.get('gcs_verbal'))
    gcs_m = safe_float(vitals.get('gcs_motor'))
    exp_e = expected.get('gcs_eyes', 4)
    exp_v = expected.get('gcs_verbal', 5)
    exp_m = expected.get('gcs_motor', 6)
    
    gcs_score = 0
    if gcs_e == exp_e and gcs_v == exp_v and gcs_m == exp_m:
        gcs_score = 15
        feedback_parts.append(f"GCS correct: E{gcs_e} V{gcs_v} M{gcs_m}")
    elif gcs_e is not None or gcs_v is not None or gcs_m is not None:
        # Partial credit if they tried but got some components wrong
        components_right = sum([1 for got, exp in [(gcs_e, exp_e), (gcs_v, exp_v), (gcs_m, exp_m)] if got == exp])
        gcs_score = components_right * 5
        feedback_parts.append(f"GCS partially correct: E{gcs_e} V{gcs_v} M{gcs_m} (Expected E{exp_e} V{exp_v} M{exp_m})")
    else:
        feedback_parts.append("GCS values missing")
        
    score += gcs_score
    subscores['gcs'] = gcs_score

    # Check for Pain Level (bonus check, not heavily penalized)
    pain = safe_float(vitals.get('pain'))
    exp_pain = expected.get('pain', 3)
    if pain == exp_pain:
        feedback_parts.append("Pain level correctly documented")

    # Ensure score is bound between 0 and 100
    score = max(0, min(100, score))
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }