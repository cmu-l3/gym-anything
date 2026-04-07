#!/usr/bin/env python3
"""
Verifier for perioperative_appendectomy_management task.

This is a very_hard task. The agent must independently manage a complete
perioperative workflow for acute appendicitis across multiple EHR modules.

Scoring breakdown (100 points total):
  - 20 pts: Acute appendicitis diagnosis (K35.x or K36/K37) for Luna
  - 20 pts: Clinical evaluation with fever (>=38.0C) AND tachycardia (>=100 bpm)
  - 20 pts: At least 3 pre-operative lab test orders
  - 20 pts: Perioperative antibiotic prescription (Ceftriaxone/Metronidazole/Piperacillin)
  - 20 pts: Post-discharge follow-up appointment within 7-14 days

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_perioperative_appendectomy_management(traj, env_info, task_info):
    """Verify perioperative appendectomy management for patient Luna."""
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
        copy_from_env('/tmp/perioperative_appendectomy_management_result.json', local_path)
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
            "feedback": "CRITICAL: Patient Luna not found — setup may have failed.",
            "subscores": {}
        }

    target_name = result.get('target_patient_name', '')
    if 'luna' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient target. Expected Luna, got: {target_name}",
            "subscores": {}
        }

    # --- Criterion 1: Appendicitis diagnosis K35.x (20 pts) ---
    k35_found = result.get('k35_found', False)
    k35_active = result.get('k35_active', False)
    k35_code = result.get('k35_code', 'none')
    any_appendicitis = result.get('any_appendicitis_found', False)
    any_appendicitis_code = result.get('any_appendicitis_code', 'none')

    if k35_found and k35_active:
        score += 20
        subscores['appendicitis_diagnosis'] = 20
        feedback_parts.append(f"Acute appendicitis diagnosis documented: ICD-10 {k35_code} (active)")
    elif k35_found:
        score += 15
        subscores['appendicitis_diagnosis'] = 15
        feedback_parts.append(f"K35 appendicitis found but NOT marked active — partial credit (code: {k35_code})")
    elif any_appendicitis:
        score += 15
        subscores['appendicitis_diagnosis'] = 15
        feedback_parts.append(f"Appendicitis diagnosis found with code {any_appendicitis_code} — acceptable alternative")
    else:
        subscores['appendicitis_diagnosis'] = 0
        feedback_parts.append("MISSING: No acute appendicitis diagnosis (K35/K36/K37) found for Luna")

    # --- Criterion 2: Clinical evaluation with fever + tachycardia (20 pts) ---
    eval_found = result.get('evaluation_found', False)
    eval_has_fever = result.get('evaluation_has_fever', False)
    eval_has_tachycardia = result.get('evaluation_has_tachycardia', False)
    eval_temp = result.get('evaluation_temperature', 'N/A')
    eval_hr = result.get('evaluation_heart_rate', 'N/A')

    if eval_found and eval_has_fever and eval_has_tachycardia:
        score += 20
        subscores['clinical_evaluation'] = 20
        feedback_parts.append(f"Clinical evaluation documented: temp={eval_temp}C (fever), HR={eval_hr} (tachycardia)")
    elif eval_found and (eval_has_fever or eval_has_tachycardia):
        score += 12
        subscores['clinical_evaluation'] = 12
        feedback_parts.append(f"Evaluation with partial vitals: temp={eval_temp}C fever={eval_has_fever}, HR={eval_hr} tachy={eval_has_tachycardia}")
    elif eval_found:
        score += 6
        subscores['clinical_evaluation'] = 6
        feedback_parts.append("Evaluation created but vital signs not documented correctly (need fever>=38C, HR>=100)")
    else:
        subscores['clinical_evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented for Luna")

    # --- Criterion 3: Pre-operative labs >= 3 (20 pts) ---
    new_lab_count = result.get('new_lab_count', 0)
    new_lab_types = result.get('new_lab_types', '')
    try:
        new_lab_count = int(new_lab_count)
    except (ValueError, TypeError):
        new_lab_count = 0

    if new_lab_count >= 3:
        score += 20
        subscores['preop_labs'] = 20
        feedback_parts.append(f"Pre-operative lab panel: {new_lab_count} tests ordered ({new_lab_types})")
    elif new_lab_count == 2:
        score += 13
        subscores['preop_labs'] = 13
        feedback_parts.append(f"Only 2 labs ordered ({new_lab_types}) — pre-op requires minimum 3 (CBC + CMP + Coag)")
    elif new_lab_count == 1:
        score += 7
        subscores['preop_labs'] = 7
        feedback_parts.append(f"Only 1 lab ordered ({new_lab_types}) — insufficient for pre-operative workup")
    else:
        subscores['preop_labs'] = 0
        feedback_parts.append("MISSING: No pre-operative labs ordered (CBC, CMP, Coagulation panel required)")

    # --- Criterion 4: Perioperative antibiotic (20 pts) ---
    prescription_found = result.get('prescription_found', False)
    antibiotic_found = result.get('antibiotic_found', False)
    antibiotic_name = result.get('antibiotic_name', 'none')

    if prescription_found and antibiotic_found:
        score += 20
        subscores['antibiotic_prophylaxis'] = 20
        feedback_parts.append(f"Perioperative antibiotic prescribed: {antibiotic_name}")
    elif prescription_found:
        score += 10
        subscores['antibiotic_prophylaxis'] = 10
        feedback_parts.append("A prescription was created but could not confirm it is a surgical antibiotic (expected Ceftriaxone/Metronidazole/Piperacillin)")
    else:
        subscores['antibiotic_prophylaxis'] = 0
        feedback_parts.append("MISSING: No perioperative antibiotic prescription for Luna")

    # --- Criterion 5: Post-discharge follow-up 7-14 days (20 pts) ---
    appt_in_range = result.get('followup_appt_in_range', False)
    appt_date = result.get('followup_appt_date', 'none')
    any_new_appts = result.get('any_new_appt_count', 0)
    try:
        any_new_appts = int(any_new_appts)
    except (ValueError, TypeError):
        any_new_appts = 0

    if appt_in_range:
        score += 20
        subscores['surgical_followup'] = 20
        feedback_parts.append(f"Post-discharge follow-up scheduled for {appt_date} (within 7-14 day window)")
    elif any_new_appts > 0:
        score += 8
        subscores['surgical_followup'] = 8
        feedback_parts.append("An appointment was scheduled but NOT in the 7-14 day post-operative window")
    else:
        subscores['surgical_followup'] = 0
        feedback_parts.append("MISSING: No post-discharge surgical follow-up appointment")

    # --- Final result ---
    passed = score >= 70
    feedback = " | ".join(feedback_parts) if feedback_parts else "No criteria met"

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "subscores": subscores,
        "target_patient": target_name,
        "clinical_note": "Acute appendicitis: K35.x Dx + pre-op labs (CBC/CMP/Coag) + perioperative Abx + clinical eval with vitals + 7-14d follow-up"
    }
