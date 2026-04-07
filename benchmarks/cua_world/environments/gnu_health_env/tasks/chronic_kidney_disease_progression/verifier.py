#!/usr/bin/env python3
"""
Verifier for chronic_kidney_disease_progression task.

This is a very_hard task. The agent must independently stage and manage CKD
requiring nephrology knowledge and navigation across multiple modules.

Scoring breakdown (100 points total):
  - 20 pts: CKD Stage 3b diagnosis (N18.x) for Ana Isabel Betz
  - 20 pts: At least 3 renal monitoring lab orders
  - 20 pts: Renoprotective prescription (ACE inhibitor or ARB)
  - 20 pts: Lifestyle/dietary counseling record
  - 20 pts: Nephrology follow-up appointment within 80-100 days (~3 months)

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_chronic_kidney_disease_progression(traj, env_info, task_info):
    """Verify CKD staging and management for patient Ana Isabel Betz."""
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
        copy_from_env('/tmp/chronic_kidney_disease_progression_result.json', local_path)
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

    target_name = result.get('target_patient_name', '')
    if 'ana' not in target_name.lower() or 'betz' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient target. Expected Ana Betz, got: {target_name}",
            "subscores": {}
        }

    # --- Criterion 1: N18 CKD diagnosis (20 pts) ---
    n18_found = result.get('n18_found', False)
    n18_active = result.get('n18_active', False)
    n18_code = result.get('n18_code', 'none')
    n18_stage_specific = result.get('n18_stage_specific', False)
    any_new_disease = result.get('any_new_disease_count', 0)
    try:
        any_new_disease = int(any_new_disease)
    except (ValueError, TypeError):
        any_new_disease = 0

    if n18_found and n18_active and n18_stage_specific:
        score += 20
        subscores['ckd_diagnosis'] = 20
        feedback_parts.append(f"CKD diagnosis with stage-specific code: ICD-10 {n18_code} (active)")
    elif n18_found and n18_active:
        score += 17
        subscores['ckd_diagnosis'] = 17
        feedback_parts.append(f"CKD diagnosis documented: N18 ({n18_code}) — stage-specific code (N18.3/N18.4) preferred")
    elif n18_found:
        score += 12
        subscores['ckd_diagnosis'] = 12
        feedback_parts.append(f"N18 CKD found ({n18_code}) but not marked active")
    elif any_new_disease > 0:
        score += 5
        subscores['ckd_diagnosis'] = 5
        feedback_parts.append("A diagnosis was added but not an N18 CKD code")
    else:
        subscores['ckd_diagnosis'] = 0
        feedback_parts.append("MISSING: No CKD diagnosis (N18.x) for Ana Isabel Betz")

    # --- Criterion 2: Renal monitoring labs >= 3 (20 pts) ---
    new_lab_count = result.get('new_lab_count', 0)
    new_lab_types = result.get('new_lab_types', '')
    try:
        new_lab_count = int(new_lab_count)
    except (ValueError, TypeError):
        new_lab_count = 0

    if new_lab_count >= 3:
        score += 20
        subscores['renal_labs'] = 20
        feedback_parts.append(f"Comprehensive renal panel: {new_lab_count} tests ordered ({new_lab_types})")
    elif new_lab_count == 2:
        score += 13
        subscores['renal_labs'] = 13
        feedback_parts.append(f"Only 2 labs ordered ({new_lab_types}) — CKD monitoring requires minimum 3 (creatinine + BUN + electrolytes)")
    elif new_lab_count == 1:
        score += 7
        subscores['renal_labs'] = 7
        feedback_parts.append(f"Only 1 lab ordered ({new_lab_types}) — insufficient for CKD monitoring")
    else:
        subscores['renal_labs'] = 0
        feedback_parts.append("MISSING: No renal monitoring labs ordered (creatinine, BUN, electrolytes, phosphorus)")

    # --- Criterion 3: Renoprotective ACEi/ARB prescription (20 pts) ---
    prescription_found = result.get('prescription_found', False)
    renoprot_found = result.get('renoprotective_found', False)
    renoprot_name = result.get('renoprotective_name', 'none')

    if prescription_found and renoprot_found:
        score += 20
        subscores['renoprotective_rx'] = 20
        feedback_parts.append(f"Renoprotective therapy prescribed: {renoprot_name}")
    elif prescription_found:
        score += 8
        subscores['renoprotective_rx'] = 8
        feedback_parts.append("A prescription was created but could not confirm ACEi/ARB for renoprotection")
    else:
        subscores['renoprotective_rx'] = 0
        feedback_parts.append("MISSING: No renoprotective prescription (ACE inhibitor or ARB) for Ana")

    # --- Criterion 4: Lifestyle/dietary counseling (20 pts) ---
    lifestyle_found = result.get('lifestyle_found', False)
    diet_info = result.get('diet_info', 'none')

    if lifestyle_found and diet_info not in ('none', 'unknown', '', 'null'):
        score += 20
        subscores['dietary_counseling'] = 20
        feedback_parts.append(f"Dietary counseling documented in lifestyle record (diet: {diet_info})")
    elif lifestyle_found:
        score += 14
        subscores['dietary_counseling'] = 14
        feedback_parts.append("Lifestyle record created but dietary information not specifically documented")
    else:
        subscores['dietary_counseling'] = 0
        feedback_parts.append("MISSING: No lifestyle/dietary counseling record for renal diet compliance")

    # --- Criterion 5: Nephrology follow-up 80-100 days (20 pts) ---
    appt_in_range = result.get('followup_appt_in_range', False)
    appt_date = result.get('followup_appt_date', 'none')
    any_new_appts = result.get('any_new_appt_count', 0)
    try:
        any_new_appts = int(any_new_appts)
    except (ValueError, TypeError):
        any_new_appts = 0

    if appt_in_range:
        score += 20
        subscores['nephrology_followup'] = 20
        feedback_parts.append(f"Nephrology follow-up scheduled for {appt_date} (within 80-100 day / ~3-month window)")
    elif any_new_appts > 0:
        score += 8
        subscores['nephrology_followup'] = 8
        feedback_parts.append("An appointment was scheduled but NOT in the 80-100 day KDIGO-recommended window")
    else:
        subscores['nephrology_followup'] = 0
        feedback_parts.append("MISSING: No nephrology follow-up appointment (KDIGO recommends 3-month intervals for Stage 3b)")

    # --- Final result ---
    passed = score >= 70
    feedback = " | ".join(feedback_parts) if feedback_parts else "No criteria met"

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "subscores": subscores,
        "target_patient": target_name,
        "clinical_note": "CKD Stage 3b: N18.x Dx + renal panel (>=3 labs) + ACEi/ARB + dietary counseling + 80-100d follow-up"
    }
