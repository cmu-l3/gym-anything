#!/usr/bin/env python3
"""
Verifier for polypharmacy_deprescribing_review task.

This is a very_hard task. The agent must independently manage a fall-related
medication safety review requiring clinical pharmacology reasoning.

Scoring breakdown (100 points total):
  - 20 pts: Fall-related injury diagnosis (W-code or S-code) for Roberto Carlos
  - 20 pts: ACE inhibitor adverse drug reaction documented in allergy profile
  - 20 pts: Safer antihypertensive prescribed (non-ACE: ARB/CCB/thiazide)
  - 20 pts: At least 2 post-fall lab orders (CBC, BMP/CMP)
  - 20 pts: Medication review follow-up appointment within 7-21 days

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_polypharmacy_deprescribing_review(traj, env_info, task_info):
    """Verify polypharmacy deprescribing review for patient Roberto Carlos."""
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
        copy_from_env('/tmp/polypharmacy_deprescribing_review_result.json', local_path)
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
            "feedback": "CRITICAL: Patient Roberto Carlos not found — setup may have failed.",
            "subscores": {}
        }

    target_name = result.get('target_patient_name', '')
    if 'roberto' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient target. Expected Roberto Carlos, got: {target_name}",
            "subscores": {}
        }

    # --- Criterion 1: Fall-related diagnosis (20 pts) ---
    fall_found = result.get('fall_diagnosis_found', False)
    fall_code = result.get('fall_diagnosis_code', 'none')
    fall_active = result.get('fall_diagnosis_active', False)
    any_new_disease = result.get('any_new_disease_count', 0)
    try:
        any_new_disease = int(any_new_disease)
    except (ValueError, TypeError):
        any_new_disease = 0

    if fall_found and fall_active:
        score += 20
        subscores['fall_diagnosis'] = 20
        feedback_parts.append(f"Fall-related injury diagnosis documented: ICD-10 {fall_code} (active)")
    elif fall_found:
        score += 15
        subscores['fall_diagnosis'] = 15
        feedback_parts.append(f"Fall diagnosis {fall_code} found but not marked active")
    elif any_new_disease > 0:
        score += 8
        subscores['fall_diagnosis'] = 8
        feedback_parts.append(f"A diagnosis was added but not a fall-related W/S code (expected W19 or S-code)")
    else:
        subscores['fall_diagnosis'] = 0
        feedback_parts.append("MISSING: No fall-related injury diagnosis for Roberto Carlos")

    # --- Criterion 2: ACE inhibitor adverse reaction (20 pts) ---
    ace_allergy_found = result.get('ace_allergy_found', False)
    ace_allergen = result.get('ace_allergen', 'none')
    ace_severity = result.get('ace_severity', 'unknown')
    any_new_allergy = result.get('any_new_allergy_count', 0)
    try:
        any_new_allergy = int(any_new_allergy)
    except (ValueError, TypeError):
        any_new_allergy = 0

    if ace_allergy_found:
        score += 20
        subscores['ace_adverse_reaction'] = 20
        feedback_parts.append(f"ACE inhibitor adverse reaction documented: {ace_allergen} (severity: {ace_severity})")
    elif any_new_allergy > 0:
        score += 10
        subscores['ace_adverse_reaction'] = 10
        feedback_parts.append("An allergy/adverse reaction was recorded but not specifically for an ACE inhibitor")
    else:
        subscores['ace_adverse_reaction'] = 0
        feedback_parts.append("MISSING: No ACE inhibitor adverse drug reaction documented")

    # --- Criterion 3: Safer antihypertensive prescription (20 pts) ---
    prescription_found = result.get('prescription_found', False)
    safe_found = result.get('safe_antihypertensive_found', False)
    safe_drug = result.get('safe_drug_name', 'none')
    ace_re_prescribed = result.get('ace_re_prescribed', 0)
    try:
        ace_re_prescribed = int(ace_re_prescribed)
    except (ValueError, TypeError):
        ace_re_prescribed = 0

    if prescription_found and safe_found and ace_re_prescribed == 0:
        score += 20
        subscores['safer_antihypertensive'] = 20
        feedback_parts.append(f"Safer antihypertensive prescribed: {safe_drug}")
    elif prescription_found and safe_found and ace_re_prescribed > 0:
        score += 10
        subscores['safer_antihypertensive'] = 10
        feedback_parts.append(f"Safe alternative prescribed ({safe_drug}) but ACE inhibitor was ALSO re-prescribed — should be discontinued")
    elif prescription_found:
        score += 8
        subscores['safer_antihypertensive'] = 8
        feedback_parts.append("A prescription was created but could not confirm it is a non-ACE antihypertensive")
    else:
        subscores['safer_antihypertensive'] = 0
        feedback_parts.append("MISSING: No safer antihypertensive prescription for Roberto Carlos")

    # --- Criterion 4: Post-fall lab orders >= 2 (20 pts) ---
    new_lab_count = result.get('new_lab_count', 0)
    new_lab_types = result.get('new_lab_types', '')
    try:
        new_lab_count = int(new_lab_count)
    except (ValueError, TypeError):
        new_lab_count = 0

    if new_lab_count >= 2:
        score += 20
        subscores['postfall_labs'] = 20
        feedback_parts.append(f"Post-fall laboratory workup: {new_lab_count} tests ordered ({new_lab_types})")
    elif new_lab_count == 1:
        score += 10
        subscores['postfall_labs'] = 10
        feedback_parts.append(f"Only 1 lab ordered ({new_lab_types}) — post-fall workup requires minimum 2 (CBC + BMP)")
    else:
        subscores['postfall_labs'] = 0
        feedback_parts.append("MISSING: No post-fall laboratory workup ordered")

    # --- Criterion 5: Medication review follow-up 7-21 days (20 pts) ---
    appt_in_range = result.get('followup_appt_in_range', False)
    appt_date = result.get('followup_appt_date', 'none')
    any_new_appts = result.get('any_new_appt_count', 0)
    try:
        any_new_appts = int(any_new_appts)
    except (ValueError, TypeError):
        any_new_appts = 0

    if appt_in_range:
        score += 20
        subscores['medication_review_followup'] = 20
        feedback_parts.append(f"Medication review follow-up scheduled for {appt_date} (within 7-21 day window)")
    elif any_new_appts > 0:
        score += 8
        subscores['medication_review_followup'] = 8
        feedback_parts.append("An appointment was scheduled but NOT in the 7-21 day window for medication review")
    else:
        subscores['medication_review_followup'] = 0
        feedback_parts.append("MISSING: No medication review follow-up appointment")

    # --- Final result ---
    passed = score >= 70
    feedback = " | ".join(feedback_parts) if feedback_parts else "No criteria met"

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "subscores": subscores,
        "target_patient": target_name,
        "clinical_note": "Geriatric fall + polypharmacy: W/S-code Dx + ACE adverse reaction + safer antihypertensive + post-fall labs + 7-21d follow-up"
    }
