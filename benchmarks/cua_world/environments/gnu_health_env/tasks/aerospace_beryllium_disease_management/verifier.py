#!/usr/bin/env python3
"""
Verifier for aerospace_beryllium_disease_management task.

This task verifies the documentation of Chronic Beryllium Disease (CBD) across
multiple EHR modules. Ensures anti-gaming via baseline ID checks.

Scoring breakdown (100 points total):
  - 20 pts: Diagnosis J63.2 (Berylliosis) for John Zenon
  - 20 pts: Evaluation recording Tachypnea (RR>=20) and Hypoxemia (SpO2<=94)
  - 20 pts: Systemic corticosteroid prescription (Prednisone/Dexamethasone, etc.)
  - 20 pts: At least 3 laboratory/diagnostic test orders
  - 20 pts: Pulmonology follow-up appointment in 14-30 days

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_aerospace_beryllium_disease_management(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    
    score = 0
    feedback_parts = []
    subscores = {}

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Extract JSON results securely
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/aerospace_beryllium_disease_management_result.json', local_path)
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

    # CRITICAL: Confirm patient context
    target_name = result.get('target_patient_name', '').lower()
    if 'john' not in target_name or 'zenon' not in target_name:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient target. Expected John Zenon, got: {target_name}"
        }

    # Criterion 1: J63.2 Diagnosis (20 pts)
    j632_found = result.get('j632_found', False)
    j63_code = result.get('j63_code', 'none')
    j63_active = result.get('j63_active', False)
    any_new_disease = result.get('any_new_disease_count', 0)

    if j632_found and j63_active:
        score += 20
        subscores['diagnosis'] = 20
        feedback_parts.append(f"Diagnosis documented: ICD-10 {j63_code} (active)")
    elif j632_found:
        score += 15
        subscores['diagnosis'] = 15
        feedback_parts.append(f"Diagnosis documented ({j63_code}) but not marked active")
    elif j63_code != 'none':
        score += 10
        subscores['diagnosis'] = 10
        feedback_parts.append(f"Related pneumoconiosis documented ({j63_code}) but not exactly J63.2 Berylliosis")
    elif any_new_disease > 0:
        score += 5
        subscores['diagnosis'] = 5
        feedback_parts.append("A diagnosis was added but not an occupational lung disease (J63.x)")
    else:
        subscores['diagnosis'] = 0
        feedback_parts.append("MISSING: No Berylliosis diagnosis (J63.2) found")

    # Criterion 2: Clinical Evaluation Vitals (20 pts)
    eval_found = result.get('eval_found', False)
    eval_rr = result.get('eval_rr', 'null')
    eval_osat = result.get('eval_osat', 'null')
    
    rr_ok, osat_ok = False, False
    try:
        if eval_rr != 'null' and float(eval_rr) >= 20: rr_ok = True
        if eval_osat != 'null' and float(eval_osat) <= 94: osat_ok = True
    except ValueError:
        pass

    if eval_found and rr_ok and osat_ok:
        score += 20
        subscores['evaluation'] = 20
        feedback_parts.append(f"Evaluation documented correctly: RR={eval_rr}, SpO2={eval_osat}%")
    elif eval_found and (rr_ok or osat_ok):
        score += 12
        subscores['evaluation'] = 12
        feedback_parts.append(f"Evaluation partial vitals: RR={eval_rr} (>=20?), SpO2={eval_osat}% (<=94?)")
    elif eval_found:
        score += 6
        subscores['evaluation'] = 6
        feedback_parts.append(f"Evaluation found but vitals incorrect (RR={eval_rr}, SpO2={eval_osat})")
    else:
        subscores['evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented")

    # Criterion 3: Corticosteroid Prescription (20 pts)
    presc_found = result.get('prescription_found', False)
    steroid_found = result.get('steroid_found', False)
    steroid_name = result.get('steroid_name', 'none')

    if presc_found and steroid_found:
        score += 20
        subscores['prescription'] = 20
        feedback_parts.append(f"Systemic corticosteroid prescribed: {steroid_name}")
    elif presc_found:
        score += 5
        subscores['prescription'] = 5
        feedback_parts.append("Prescription created but no corticosteroid identified")
    else:
        subscores['prescription'] = 0
        feedback_parts.append("MISSING: No medications prescribed")

    # Criterion 4: Lab/Diagnostic Orders >= 3 (20 pts)
    lab_count = result.get('new_lab_count', 0)
    lab_types = result.get('new_lab_types', '')
    
    if lab_count >= 3:
        score += 20
        subscores['labs'] = 20
        feedback_parts.append(f"Diagnostic orders fulfilled: {lab_count} ordered ({lab_types})")
    elif lab_count > 0:
        score += int((lab_count / 3.0) * 20)
        subscores['labs'] = subscores.get('labs', 0)
        feedback_parts.append(f"Partial diagnostics ordered: {lab_count}/3 ordered ({lab_types})")
    else:
        subscores['labs'] = 0
        feedback_parts.append("MISSING: No diagnostic tests ordered")

    # Criterion 5: Follow-up Appointment 14-30 days (20 pts)
    appt_found = result.get('appt_found', False)
    days_out_str = result.get('appt_days_out', 'null')
    appt_date = result.get('appt_date', 'null')
    
    if appt_found and days_out_str != 'null':
        try:
            days_out = int(days_out_str)
            if 14 <= days_out <= 30:
                score += 20
                subscores['appointment'] = 20
                feedback_parts.append(f"Follow-up scheduled correctly for {appt_date} ({days_out} days out)")
            elif 7 <= days_out <= 45:
                score += 10
                subscores['appointment'] = 10
                feedback_parts.append(f"Follow-up scheduled for {appt_date} ({days_out} days out) - slightly outside 14-30 day window")
            else:
                score += 5
                subscores['appointment'] = 5
                feedback_parts.append(f"Follow-up scheduled for {appt_date} ({days_out} days out) - outside valid window")
        except ValueError:
            feedback_parts.append("Appointment found but days diff could not be parsed")
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