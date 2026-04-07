#!/usr/bin/env python3
"""
Verifier for record_newborn_delivery task.

Scoring breakdown (100 points total):
  - 20 pts: Newborn record created and linked to Mother (Ana Isabel Betz)
  - 20 pts: Birth measurements recorded (weight, length, CP) within +/- 10%
  - 20 pts: APGAR scores (1 min & 5 min) recorded accurately (+/- 1 point)
  - 20 pts: Infant registered as a formal patient ("Sofia Betz")
  - 20 pts: Follow-up appointment scheduled for the infant in 28-35 days

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def parse_float(val, default=0.0):
    try:
        if val is None or val == 'null' or val == '':
            return default
        return float(val)
    except (ValueError, TypeError):
        return default

def verify_record_newborn_delivery(traj, env_info, task_info):
    """Verify neonatal workflow completion for newborn Sofia Betz."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    metadata = task_info.get('metadata', {})
    expected_weight_g = metadata.get('expected_weight_g', 3200)
    expected_length_cm = metadata.get('expected_length_cm', 49)
    expected_cp_cm = metadata.get('expected_cp_cm', 34)
    expected_apgar1 = metadata.get('expected_apgar1', 8)
    expected_apgar5 = metadata.get('expected_apgar5', 9)

    score = 0
    feedback_parts = []
    subscores = {}

    # Copy result JSON from VM
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/record_newborn_delivery_result.json', local_path)
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

    # --- Criterion 1: Newborn Record Created (20 pts) ---
    nb_found = result.get('newborn_record_found', False)
    any_nb_count = result.get('any_new_newborn_count', 0)
    
    if nb_found:
        score += 20
        subscores['newborn_record'] = 20
        feedback_parts.append("Newborn record correctly created and linked to mother Ana Isabel Betz")
    elif any_nb_count > 0:
        score += 5
        subscores['newborn_record'] = 5
        feedback_parts.append(f"A newborn record was created, but NOT linked to Ana Isabel Betz")
    else:
        subscores['newborn_record'] = 0
        feedback_parts.append("MISSING: No newborn record created for Ana Isabel Betz")

    # --- Criterion 2: Birth Measurements (20 pts) ---
    w_val = parse_float(result.get('newborn_weight', 'null'))
    l_val = parse_float(result.get('newborn_length', 'null'))
    cp_val = parse_float(result.get('newborn_cp', 'null'))
    
    # Handle weight (agent might enter 3200 grams or 3.2 kg depending on UI expectation)
    w_ok = (2880 <= w_val <= 3520) or (2.88 <= w_val <= 3.52)
    l_ok = (44.1 <= l_val <= 53.9) # 49 +/- 10%
    cp_ok = (30.6 <= cp_val <= 37.4) # 34 +/- 10%
    
    if nb_found:
        measurements_matched = sum([1 for m in [w_ok, l_ok, cp_ok] if m])
        if measurements_matched == 3:
            score += 20
            subscores['measurements'] = 20
            feedback_parts.append("All birth measurements (Weight, Length, CP) recorded accurately")
        elif measurements_matched > 0:
            pts = int((measurements_matched / 3) * 20)
            score += pts
            subscores['measurements'] = pts
            feedback_parts.append(f"Birth measurements partially recorded ({measurements_matched}/3 accurate)")
        else:
            subscores['measurements'] = 0
            feedback_parts.append("Birth measurements missing or outside acceptable ranges")
    else:
        subscores['measurements'] = 0
        feedback_parts.append("MISSING: Measurements cannot be verified without newborn record")

    # --- Criterion 3: APGAR Scores (20 pts) ---
    apgar1_val = parse_float(result.get('newborn_apgar1', 'null'), -1)
    apgar5_val = parse_float(result.get('newborn_apgar5', 'null'), -1)
    
    apgar1_ok = abs(apgar1_val - expected_apgar1) <= 1
    apgar5_ok = abs(apgar5_val - expected_apgar5) <= 1
    
    if nb_found:
        if apgar1_ok and apgar5_ok:
            score += 20
            subscores['apgar_scores'] = 20
            feedback_parts.append("APGAR scores (1-min and 5-min) recorded accurately")
        elif apgar1_ok or apgar5_ok:
            score += 10
            subscores['apgar_scores'] = 10
            feedback_parts.append("APGAR scores partially recorded (1 of 2 accurate)")
        else:
            subscores['apgar_scores'] = 0
            feedback_parts.append("APGAR scores missing or incorrect")
    else:
        subscores['apgar_scores'] = 0

    # --- Criterion 4: Patient Registration (20 pts) ---
    patient_registered = result.get('patient_registered', False)
    sofia_id = result.get('sofia_patient_id', 0)
    sofia_sex = result.get('sofia_sex', 'none')
    
    if patient_registered:
        score += 20
        subscores['patient_registration'] = 20
        feedback_parts.append("Infant successfully registered as formal patient 'Sofia Betz'")
    elif sofia_id != 0:
        score += 15
        subscores['patient_registration'] = 15
        feedback_parts.append("Infant registered with partial name match (First or Last name matched)")
    else:
        subscores['patient_registration'] = 0
        feedback_parts.append("MISSING: Infant was not formally registered as a patient in the system")

    # --- Criterion 5: Well-Baby Follow-up Appointment (20 pts) ---
    appt_scheduled = result.get('appointment_scheduled', False)
    days_diff = result.get('appointment_days_diff', -1)
    any_appt_count = result.get('any_new_appt_count', 0)
    
    if appt_scheduled and (28 <= days_diff <= 35):
        score += 20
        subscores['appointment'] = 20
        feedback_parts.append(f"Well-baby follow-up scheduled correctly ({days_diff} days from today)")
    elif appt_scheduled:
        score += 10
        subscores['appointment'] = 10
        feedback_parts.append(f"Follow-up scheduled for infant, but timing is off ({days_diff} days, expected 28-35)")
    elif any_appt_count > 0:
        score += 5
        subscores['appointment'] = 5
        feedback_parts.append("An appointment was scheduled, but NOT for the correct infant patient record")
    else:
        subscores['appointment'] = 0
        feedback_parts.append("MISSING: No follow-up appointment scheduled")

    # Determine pass/fail
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts),
        "subscores": subscores
    }