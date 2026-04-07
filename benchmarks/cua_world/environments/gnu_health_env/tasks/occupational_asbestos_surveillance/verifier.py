#!/usr/bin/env python3
"""
Verifier for occupational_asbestos_surveillance task.

Scoring breakdown (100 points total):
  - 25 pts: Asbestos-related Diagnosis (Pleural plaque J92.x or pneumoconiosis J61)
  - 20 pts: Respiratory vitals logged (RR and SpO2)
  - 15 pts: Baseline lab ordered (at least 1 new lab)
  - 20 pts: Smoking status documented (new/updated lifestyle record)
  - 20 pts: Annual surveillance scheduled (~1 year / 330-400 days)

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile
import datetime

logger = logging.getLogger(__name__)

def verify_occupational_asbestos_surveillance(traj, env_info, task_info):
    """Verify occupational asbestos medical surveillance protocol."""
    copy_from_env = env_info.get('copy_from_env')
    
    score = 0
    feedback_parts = []
    subscores = {}

    # Copy result JSON from VM
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/occupational_asbestos_surveillance_result.json', local_path)
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
            "feedback": "CRITICAL: Patient Roberto Carlos not found — setup may have failed.",
            "subscores": {}
        }

    # --- Criterion 1: Asbestos-related diagnosis (25 pts) ---
    asb_found = result.get('asb_found', False)
    asb_active = result.get('asb_active', False)
    asb_code = result.get('asb_code', 'none')
    any_new_disease = result.get('any_new_disease_count', 0)

    try:
        any_new_disease = int(any_new_disease)
    except (ValueError, TypeError):
        any_new_disease = 0

    if asb_found and asb_active:
        score += 25
        subscores['diagnosis'] = 25
        feedback_parts.append(f"Asbestos diagnosis documented: ICD-10 {asb_code} (active)")
    elif asb_found:
        score += 15
        subscores['diagnosis'] = 15
        feedback_parts.append(f"Asbestos diagnosis {asb_code} found but not marked active")
    elif any_new_disease > 0:
        score += 5
        subscores['diagnosis'] = 5
        feedback_parts.append("A diagnosis was added, but not a pleural plaque or pneumoconiosis (J92/J61) code")
    else:
        subscores['diagnosis'] = 0
        feedback_parts.append("MISSING: No asbestos-related condition (J92.x/J61) documented for Roberto")

    # --- Criterion 2: Respiratory vitals logged (20 pts) ---
    eval_found = result.get('eval_found', False)
    eval_rr = result.get('eval_rr', 'null')
    eval_spo2 = result.get('eval_spo2', 'null')
    
    has_rr = eval_rr != 'null' and str(eval_rr).strip() != ''
    has_spo2 = eval_spo2 != 'null' and str(eval_spo2).strip() != ''

    if eval_found and has_rr and has_spo2:
        score += 20
        subscores['respiratory_vitals'] = 20
        feedback_parts.append(f"Respiratory vitals logged (RR={eval_rr}, SpO2={eval_spo2})")
    elif eval_found and (has_rr or has_spo2):
        score += 10
        subscores['respiratory_vitals'] = 10
        feedback_parts.append(f"Evaluation has partial vitals (RR={eval_rr}, SpO2={eval_spo2})")
    elif eval_found:
        score += 5
        subscores['respiratory_vitals'] = 5
        feedback_parts.append("Evaluation created, but respiratory vitals are missing")
    else:
        subscores['respiratory_vitals'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented")

    # --- Criterion 3: Baseline Lab Ordered (15 pts) ---
    new_lab_count = result.get('new_lab_count', 0)
    try:
        new_lab_count = int(new_lab_count)
    except (ValueError, TypeError):
        new_lab_count = 0

    if new_lab_count >= 1:
        score += 15
        subscores['baseline_lab'] = 15
        feedback_parts.append(f"Cardiopulmonary screening documented: {new_lab_count} lab(s) ordered")
    else:
        subscores['baseline_lab'] = 0
        feedback_parts.append("MISSING: No baseline labs ordered")

    # --- Criterion 4: Smoking status in Lifestyle (20 pts) ---
    lifestyle_found = result.get('lifestyle_found', False)

    if lifestyle_found:
        score += 20
        subscores['lifestyle'] = 20
        feedback_parts.append("Patient lifestyle record added/updated (smoking status)")
    else:
        subscores['lifestyle'] = 0
        feedback_parts.append("MISSING: Patient lifestyle (tobacco/smoking history) not documented")

    # --- Criterion 5: Annual Surveillance Follow-up (20 pts) ---
    appt_found = result.get('appt_found', False)
    appt_date_str = result.get('appt_date', 'null')
    task_start_str = result.get('task_start_date', '')

    if appt_found and appt_date_str != 'null' and task_start_str:
        try:
            appt_date = datetime.datetime.strptime(appt_date_str, '%Y-%m-%d')
            start_date = datetime.datetime.strptime(task_start_str, '%Y-%m-%d')
            delta_days = (appt_date - start_date).days

            if 330 <= delta_days <= 400:
                score += 20
                subscores['follow_up'] = 20
                feedback_parts.append(f"Annual surveillance follow-up scheduled correctly ({delta_days} days)")
            elif 250 <= delta_days <= 450:
                score += 10
                subscores['follow_up'] = 10
                feedback_parts.append(f"Follow-up scheduled in {delta_days} days — expected ~365 days (1 year)")
            else:
                score += 5
                subscores['follow_up'] = 5
                feedback_parts.append(f"Follow-up scheduled, but timeframe is inappropriate for annual surveillance ({delta_days} days)")
        except Exception:
            score += 5
            subscores['follow_up'] = 5
            feedback_parts.append(f"Follow-up appointment found, but date parsing failed ({appt_date_str})")
    else:
        subscores['follow_up'] = 0
        feedback_parts.append("MISSING: No follow-up appointment scheduled")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }