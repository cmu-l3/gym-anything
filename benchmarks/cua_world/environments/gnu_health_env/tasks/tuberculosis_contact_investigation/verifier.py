#!/usr/bin/env python3
"""
Verifier for tuberculosis_contact_investigation task.

This is a very_hard task. The agent must independently manage an active TB case
requiring multi-drug regimen, contact tracing, and public health protocol.

Scoring breakdown (100 points total):
  - 20 pts: Active pulmonary TB diagnosis (A15.x) for Matt Betz
  - 20 pts: RIPE regimen — at least 3 of 4 drugs prescribed
  - 20 pts: At least 2 sputum/microbiological lab orders
  - 20 pts: Family disease history entry for TB household contact
  - 20 pts: Treatment response follow-up appointment within 10-21 days

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_tuberculosis_contact_investigation(traj, env_info, task_info):
    """Verify TB contact investigation protocol for patient Matt Zenon Betz."""
    copy_from_env = env_info.get('copy_from_env')
    metadata = task_info.get('metadata', {})

    score = 0
    feedback_parts = []
    subscores = {}

    # --- Copy result JSON from VM ---
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/tuberculosis_contact_investigation_result.json', local_path)
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
            "feedback": "CRITICAL: Patient Matt Betz not found — setup may have failed.",
            "subscores": {}
        }

    target_name = result.get('target_patient_name', '')
    if 'matt' not in target_name.lower() or 'betz' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient target. Expected Matt Betz, got: {target_name}",
            "subscores": {}
        }

    # --- Criterion 1: A15 TB diagnosis (20 pts) ---
    a15_found = result.get('a15_found', False)
    a15_active = result.get('a15_active', False)
    a15_code = result.get('a15_code', 'none')
    any_tb = result.get('any_tb_found', False)
    any_tb_code = result.get('any_tb_code', 'none')

    if a15_found and a15_active:
        score += 20
        subscores['tb_diagnosis'] = 20
        feedback_parts.append(f"Active pulmonary TB diagnosis documented: ICD-10 {a15_code}")
    elif a15_found:
        score += 15
        subscores['tb_diagnosis'] = 15
        feedback_parts.append(f"A15 TB diagnosis found but NOT marked active (code: {a15_code})")
    elif any_tb:
        score += 12
        subscores['tb_diagnosis'] = 12
        feedback_parts.append(f"TB-related diagnosis found ({any_tb_code}) — A15 would be more specific for pulmonary TB")
    else:
        subscores['tb_diagnosis'] = 0
        feedback_parts.append("MISSING: No pulmonary TB diagnosis (A15.x) found for Matt Betz")

    # --- Criterion 2: RIPE regimen — at least 3 of 4 drugs (20 pts) ---
    ripe_count = result.get('ripe_drug_count', 0)
    ripe_drugs = result.get('ripe_drugs_found', '')
    total_presc = result.get('total_new_prescriptions', 0)
    try:
        ripe_count = int(ripe_count)
        total_presc = int(total_presc)
    except (ValueError, TypeError):
        ripe_count = 0
        total_presc = 0

    if ripe_count >= 4:
        score += 20
        subscores['ripe_regimen'] = 20
        feedback_parts.append(f"Complete RIPE regimen: all 4 drugs prescribed ({ripe_drugs})")
    elif ripe_count == 3:
        score += 17
        subscores['ripe_regimen'] = 17
        feedback_parts.append(f"RIPE regimen: 3 of 4 drugs prescribed ({ripe_drugs}) — acceptable for intensive phase")
    elif ripe_count == 2:
        score += 10
        subscores['ripe_regimen'] = 10
        feedback_parts.append(f"Only 2 RIPE drugs found ({ripe_drugs}) — TB requires minimum 3-drug regimen")
    elif ripe_count == 1:
        score += 5
        subscores['ripe_regimen'] = 5
        feedback_parts.append(f"Only 1 RIPE drug found ({ripe_drugs}) — TB monotherapy is contraindicated")
    elif total_presc > 0:
        score += 3
        subscores['ripe_regimen'] = 3
        feedback_parts.append(f"Prescriptions created ({total_presc}) but no RIPE drugs identified")
    else:
        subscores['ripe_regimen'] = 0
        feedback_parts.append("MISSING: No anti-TB medications prescribed (RIPE: Rifampin, Isoniazid, Pyrazinamide, Ethambutol)")

    # --- Criterion 3: Sputum/microbiological labs >= 2 (20 pts) ---
    new_lab_count = result.get('new_lab_count', 0)
    new_lab_types = result.get('new_lab_types', '')
    try:
        new_lab_count = int(new_lab_count)
    except (ValueError, TypeError):
        new_lab_count = 0

    if new_lab_count >= 2:
        score += 20
        subscores['sputum_labs'] = 20
        feedback_parts.append(f"Microbiological workup: {new_lab_count} lab orders ({new_lab_types})")
    elif new_lab_count == 1:
        score += 10
        subscores['sputum_labs'] = 10
        feedback_parts.append(f"Only 1 lab ordered ({new_lab_types}) — TB requires minimum 2 (AFB culture + smear)")
    else:
        subscores['sputum_labs'] = 0
        feedback_parts.append("MISSING: No sputum/microbiological labs ordered (AFB culture and smear required)")

    # --- Criterion 4: Family disease history — contact tracing (20 pts) ---
    family_tb = result.get('family_tb_contact_found', False)
    family_code = result.get('family_tb_code', 'none')
    any_family = result.get('any_new_family_disease', 0)
    try:
        any_family = int(any_family)
    except (ValueError, TypeError):
        any_family = 0

    if family_tb:
        score += 20
        subscores['contact_investigation'] = 20
        feedback_parts.append(f"Household contact documented in family disease history: {family_code}")
    elif any_family > 0:
        score += 10
        subscores['contact_investigation'] = 10
        feedback_parts.append("Family disease history added but not specifically for TB/contact exposure")
    else:
        subscores['contact_investigation'] = 0
        feedback_parts.append("MISSING: No household contact investigation documented in family disease history")

    # --- Criterion 5: Treatment follow-up 10-21 days (20 pts) ---
    appt_in_range = result.get('followup_appt_in_range', False)
    appt_date = result.get('followup_appt_date', 'none')
    any_new_appts = result.get('any_new_appt_count', 0)
    try:
        any_new_appts = int(any_new_appts)
    except (ValueError, TypeError):
        any_new_appts = 0

    if appt_in_range:
        score += 20
        subscores['treatment_followup'] = 20
        feedback_parts.append(f"Treatment response evaluation scheduled for {appt_date} (within 10-21 day window)")
    elif any_new_appts > 0:
        score += 8
        subscores['treatment_followup'] = 8
        feedback_parts.append("An appointment was scheduled but NOT in the 10-21 day treatment evaluation window")
    else:
        subscores['treatment_followup'] = 0
        feedback_parts.append("MISSING: No treatment response follow-up appointment scheduled")

    # --- Final result ---
    passed = score >= 70
    feedback = " | ".join(feedback_parts) if feedback_parts else "No criteria met"

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "subscores": subscores,
        "target_patient": target_name,
        "clinical_note": "Active pulmonary TB: A15.x Dx + RIPE regimen (>=3 drugs) + sputum labs + contact investigation + 10-21d follow-up"
    }
