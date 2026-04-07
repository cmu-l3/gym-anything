#!/usr/bin/env python3
"""
Verifier for occupational_shift_work_sleep_disorder task.

This task evaluates the documentation and management of Shift Work Sleep Disorder
in an occupational health setting.

Scoring breakdown (100 points total):
  - 15 pts: Diagnosis of G47.x (preferably G47.2 Circadian rhythm sleep disorder)
  - 15 pts: Clinical evaluation documenting fatigue / near-miss
  - 20 pts: At least 2 lab orders including CBC and Thyroid/TSH (rule-out tests)
  - 20 pts: SWSD Prescription (Modafinil, Armodafinil, Melatonin)
  - 15 pts: Lifestyle counseling record (sleep hygiene / shift work)
  - 15 pts: Follow-up appointment scheduled within 14-30 days

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_occupational_shift_work_sleep_disorder(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    metadata = task_info.get('metadata', {})

    score = 0
    feedback_parts = []
    subscores = {}

    # Copy result JSON from VM
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/occupational_shift_work_sleep_disorder_result.json', local_path)
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

    # CRITICAL CHECK: Correct patient
    target_id = result.get('target_patient_id', 0)
    if not target_id or target_id == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "CRITICAL: Patient Bonifacio Caput not found — setup may have failed.",
            "subscores": {}
        }

    target_name = result.get('target_patient_name', '')
    if 'bonifacio' not in target_name.lower() or 'caput' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient target. Expected Bonifacio Caput, got: {target_name}",
            "subscores": {}
        }

    # Criterion 1: G47.x Diagnosis (15 pts)
    g47_found = result.get('g47_found', False)
    g47_active = result.get('g47_active', False)
    g47_code = result.get('g47_code', 'none')
    g472_specific = result.get('g472_specific', False)
    any_new_disease = int(result.get('any_new_disease_count', 0))

    if g47_found and g47_active and g472_specific:
        score += 15
        subscores['diagnosis'] = 15
        feedback_parts.append(f"Circadian rhythm sleep disorder diagnosis documented: ICD-10 {g47_code} (active)")
    elif g47_found and g47_active:
        score += 12
        subscores['diagnosis'] = 12
        feedback_parts.append(f"Sleep disorder diagnosis documented: {g47_code} (active) — G47.2 preferred for shift work")
    elif g47_found:
        score += 8
        subscores['diagnosis'] = 8
        feedback_parts.append(f"Diagnosis {g47_code} found but not marked active")
    elif any_new_disease > 0:
        score += 3
        subscores['diagnosis'] = 3
        feedback_parts.append("A diagnosis was added but not a G47 sleep disorder code")
    else:
        subscores['diagnosis'] = 0
        feedback_parts.append("MISSING: No sleep disorder diagnosis (G47.x) for Bonifacio Caput")

    # Criterion 2: Clinical evaluation (15 pts)
    eval_found = result.get('evaluation_found', False)
    eval_notes = result.get('evaluation_notes', '').lower()

    if eval_found and ('fatigue' in eval_notes or 'sleep' in eval_notes or 'miss' in eval_notes or 'shift' in eval_notes):
        score += 15
        subscores['evaluation'] = 15
        feedback_parts.append("Clinical evaluation documented with relevant clinical narrative (fatigue/sleep/near-miss)")
    elif eval_found:
        score += 10
        subscores['evaluation'] = 10
        feedback_parts.append("Clinical evaluation created but narrative lacked specific details about fatigue/near-miss")
    else:
        subscores['evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented")

    # Criterion 3: Lab orders (20 pts)
    new_lab_count = int(result.get('new_lab_count', 0))
    new_lab_types = result.get('new_lab_types', '').lower()
    new_lab_names = result.get('new_lab_names', '').lower()

    has_cbc = 'cbc' in new_lab_types or 'blood count' in new_lab_names
    has_tsh = 'tsh' in new_lab_types or 'thyroid' in new_lab_names

    if new_lab_count >= 2 and has_cbc and has_tsh:
        score += 20
        subscores['labs'] = 20
        feedback_parts.append("Comprehensive rule-out lab panel ordered (CBC and Thyroid/TSH)")
    elif new_lab_count >= 2 and (has_cbc or has_tsh):
        score += 15
        subscores['labs'] = 15
        feedback_parts.append(f"Labs ordered ({new_lab_count}) but missing one of the specific rule-out tests (CBC or TSH)")
    elif new_lab_count >= 2:
        score += 10
        subscores['labs'] = 10
        feedback_parts.append(f"Labs ordered ({new_lab_count}) but missing both key rule-out tests (CBC and TSH)")
    elif new_lab_count == 1:
        score += 5
        subscores['labs'] = 5
        feedback_parts.append(f"Only 1 lab ordered — insufficient for fatigue workup")
    else:
        subscores['labs'] = 0
        feedback_parts.append("MISSING: No baseline labs ordered (CBC/TSH required)")

    # Criterion 4: Prescription (20 pts)
    prescription_found = result.get('prescription_found', False)
    swsd_drug_found = result.get('swsd_drug_found', False)
    swsd_drug_name = result.get('swsd_drug_name', 'none')

    if prescription_found and swsd_drug_found:
        score += 20
        subscores['prescription'] = 20
        feedback_parts.append(f"SWSD pharmacotherapy prescribed: {swsd_drug_name}")
    elif prescription_found:
        score += 5
        subscores['prescription'] = 5
        feedback_parts.append("Prescription created but did not include Modafinil, Armodafinil, or Melatonin")
    else:
        subscores['prescription'] = 0
        feedback_parts.append("MISSING: No SWSD medication prescribed")

    # Criterion 5: Lifestyle counseling (15 pts)
    lifestyle_found = result.get('lifestyle_found', False)
    any_new_lifestyle = int(result.get('any_new_lifestyle_count', 0))
    lifestyle_info = result.get('lifestyle_info', '').lower()

    if lifestyle_found and ('sleep' in lifestyle_info or 'shift' in lifestyle_info or 'hygiene' in lifestyle_info):
        score += 15
        subscores['lifestyle'] = 15
        feedback_parts.append("Lifestyle counseling documented (sleep hygiene/shift adaptation)")
    elif any_new_lifestyle > 0:
        score += 10
        subscores['lifestyle'] = 10
        feedback_parts.append("Lifestyle record created but missing specific notes on sleep hygiene or shift work")
    else:
        subscores['lifestyle'] = 0
        feedback_parts.append("MISSING: No lifestyle/counseling record documented")

    # Criterion 6: Follow-up Appointment (15 pts)
    appt_found = result.get('appt_found', False)
    appt_days_diff = int(result.get('appt_days_diff', 0))
    total_new_appts = int(result.get('total_new_appts', 0))

    if appt_found and 14 <= appt_days_diff <= 30:
        score += 15
        subscores['appointment'] = 15
        feedback_parts.append(f"Follow-up appointment scheduled appropriately ({appt_days_diff} days)")
    elif appt_found and appt_days_diff > 30:
        score += 10
        subscores['appointment'] = 10
        feedback_parts.append(f"Follow-up scheduled ({appt_days_diff} days) — slightly late (expected 14-30 days)")
    elif appt_found and appt_days_diff < 14:
        score += 10
        subscores['appointment'] = 10
        feedback_parts.append(f"Follow-up scheduled ({appt_days_diff} days) — slightly early (expected 14-30 days)")
    elif total_new_appts > 0:
        score += 5
        subscores['appointment'] = 5
        feedback_parts.append(f"Appointment created but date could not be verified")
    else:
        subscores['appointment'] = 0
        feedback_parts.append("MISSING: No follow-up appointment scheduled")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }