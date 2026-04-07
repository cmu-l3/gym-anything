#!/usr/bin/env python3
"""
Verifier for occupational_diver_decompression_illness task.

Scoring breakdown (100 points total):
  - 20 pts: Decompression sickness diagnosis (T70.3 or T70.x) for John Zenon
  - 20 pts: Clinical evaluation documenting HR, RR, and SpO2
  - 20 pts: Prescribed acute therapy (Oxygen or Sodium Chloride)
  - 20 pts: At least 2 baseline laboratory orders
  - 20 pts: Reassessment follow-up appointment within 1-2 days

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_occupational_diver_decompression_illness(traj, env_info, task_info):
    """Verify occupational decompression illness management for John Zenon."""
    copy_from_env = env_info.get('copy_from_env')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }

    score = 0
    feedback_parts = []
    subscores = {}

    # Copy result JSON from VM
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/occupational_diver_decompression_illness_result.json', local_path)
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

    # CRITICAL CHECK: Correct patient target
    target_id = result.get('target_patient_id', 0)
    target_name = result.get('target_patient_name', '')
    
    if not target_id or target_id == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "CRITICAL: Target patient not found in database — setup may have failed.",
            "subscores": {}
        }

    if 'john' not in target_name.lower() or 'zenon' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient target. Expected John Zenon, got: {target_name}",
            "subscores": {}
        }

    # Criterion 1: T70.x diagnosis (20 pts)
    t70_found = result.get('t70_found', False)
    t70_active = result.get('t70_active', False)
    t70_code = result.get('t70_code', 'none')
    t70_3_specific = result.get('t70_3_specific', False)

    if t70_found and t70_active and t70_3_specific:
        score += 20
        subscores['diagnosis'] = 20
        feedback_parts.append(f"Decompression sickness diagnosis documented: ICD-10 {t70_code} (active)")
    elif t70_found and t70_active:
        score += 15
        subscores['diagnosis'] = 15
        feedback_parts.append(f"T70 barotrauma diagnosis found ({t70_code}), but T70.3 is more specific")
    elif t70_found:
        score += 10
        subscores['diagnosis'] = 10
        feedback_parts.append(f"T70 diagnosis found ({t70_code}) but NOT marked active")
    else:
        subscores['diagnosis'] = 0
        feedback_parts.append("MISSING: No T70.x decompression sickness diagnosis found for John Zenon")

    # Criterion 2: Clinical evaluation with vitals (20 pts)
    eval_found = result.get('evaluation_found', False)
    hr = result.get('evaluation_heart_rate', 'null')
    rr = result.get('evaluation_respiratory_rate', 'null')
    spo2 = result.get('evaluation_oxygen_saturation', 'null')

    vitals_count = sum([1 for v in [hr, rr, spo2] if v and str(v).lower() != 'null'])

    if eval_found and vitals_count == 3:
        score += 20
        subscores['evaluation'] = 20
        feedback_parts.append(f"Clinical evaluation documented with all vitals: HR={hr}, RR={rr}, SpO2={spo2}")
    elif eval_found and vitals_count > 0:
        score += 10
        subscores['evaluation'] = 10
        feedback_parts.append(f"Evaluation documented, but incomplete vitals (found {vitals_count}/3)")
    elif eval_found:
        score += 5
        subscores['evaluation'] = 5
        feedback_parts.append("Clinical evaluation created but no vitals recorded")
    else:
        subscores['evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented")

    # Criterion 3: Acute therapy prescription (20 pts)
    prescription_found = result.get('prescription_found', False)
    therapy_found = result.get('therapy_found', False)
    therapy_drug = result.get('therapy_drug_name', 'none')

    if prescription_found and therapy_found:
        score += 20
        subscores['prescription'] = 20
        feedback_parts.append(f"Acute therapy prescribed: {therapy_drug}")
    elif prescription_found:
        score += 10
        subscores['prescription'] = 10
        feedback_parts.append("Prescription created but did not include Oxygen or Sodium Chloride")
    else:
        subscores['prescription'] = 0
        feedback_parts.append("MISSING: No therapeutic prescription found")

    # Criterion 4: Baseline labs >= 2 (20 pts)
    lab_count = result.get('new_lab_count', 0)
    lab_types = result.get('new_lab_types', '')
    
    try:
        lab_count = int(lab_count)
    except (ValueError, TypeError):
        lab_count = 0

    if lab_count >= 2:
        score += 20
        subscores['labs'] = 20
        feedback_parts.append(f"Baseline lab workup completed: {lab_count} orders ({lab_types})")
    elif lab_count == 1:
        score += 10
        subscores['labs'] = 10
        feedback_parts.append(f"Only 1 lab test ordered ({lab_types}) — requires at least 2")
    else:
        subscores['labs'] = 0
        feedback_parts.append("MISSING: No lab requests created")

    # Criterion 5: Reassessment follow-up 1-2 days (20 pts)
    appt_found = result.get('appointment_found', False)
    diff_days = result.get('appointment_diff_days', -999)

    try:
        diff_days = int(diff_days)
    except (ValueError, TypeError):
        diff_days = -999

    if appt_found and 1 <= diff_days <= 2:
        score += 20
        subscores['appointment'] = 20
        feedback_parts.append(f"Reassessment follow-up scheduled appropriately (in {diff_days} days)")
    elif appt_found and diff_days >= 0:
        score += 10
        subscores['appointment'] = 10
        feedback_parts.append(f"Follow-up scheduled, but timeframe is incorrect (in {diff_days} days, expected 1-2)")
    elif appt_found:
        score += 5
        subscores['appointment'] = 5
        feedback_parts.append("Follow-up appointment found but date is in the past or invalid")
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