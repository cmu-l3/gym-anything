#!/usr/bin/env python3
"""
Verifier for industrial_water_contamination_response task.

This task evaluates the ability of the agent to accurately document an environmental
waterborne pathogen exposure by interacting across 5 distinct EHR modules.

Scoring breakdown (100 points total):
  - 20 pts: Diagnosis for Giardiasis/Gastroenteritis (A07.x or A09) marked active.
  - 20 pts: Dehydration vitals (Heart rate >= 100 AND Systolic <= 100) recorded in an evaluation.
  - 20 pts: Polypharmacy prescription containing Metronidazole + 1 other med (>= 2 lines).
  - 20 pts: Diagnostic laboratory test ordered (>= 1 order).
  - 20 pts: Follow-up appointment scheduled 1 to 3 days from the task date.

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_industrial_water_contamination_response(traj, env_info, task_info):
    """Verify workplace water contamination incident protocol for Bonifacio Caput."""
    copy_from_env = env_info.get('copy_from_env')

    score = 0
    feedback_parts = []
    subscores = {}

    # --- Copy result JSON from VM ---
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/industrial_water_contamination_response_result.json', local_path)
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

    # --- Criterion 1: Diagnosis (20 pts) ---
    diagnosis_found = result.get('diagnosis_found', False)
    diagnosis_code = result.get('diagnosis_code', 'none')
    diagnosis_active = result.get('diagnosis_active', False)
    any_new_disease_count = result.get('any_new_disease_count', 0)

    if diagnosis_found and diagnosis_active:
        score += 20
        subscores['diagnosis'] = 20
        feedback_parts.append(f"Diagnosis documented: ICD-10 {diagnosis_code} (active)")
    elif diagnosis_found:
        score += 10
        subscores['diagnosis'] = 10
        feedback_parts.append(f"Diagnosis {diagnosis_code} found but not marked active")
    elif any_new_disease_count > 0:
        score += 5
        subscores['diagnosis'] = 5
        feedback_parts.append(f"A diagnosis was added, but not A07/A09 (Waterborne Pathogen/Gastroenteritis)")
    else:
        subscores['diagnosis'] = 0
        feedback_parts.append("MISSING: No gastrointestinal diagnosis (A07/A09) found")

    # --- Criterion 2: Clinical Evaluation Vitals (20 pts) ---
    eval_found = result.get('eval_found', False)
    eval_hr_str = result.get('eval_hr', 'null')
    eval_sys_str = result.get('eval_sys', 'null')

    if eval_found:
        try:
            hr_val = float(eval_hr_str) if eval_hr_str != 'null' else 0
            sys_val = float(eval_sys_str) if eval_sys_str != 'null' else 999
            
            tachycardic = hr_val >= 100
            hypotensive = sys_val <= 100

            if tachycardic and hypotensive:
                score += 20
                subscores['clinical_evaluation'] = 20
                feedback_parts.append(f"Dehydration vitals recorded: HR {hr_val} bpm, Sys BP {sys_val} mmHg")
            elif tachycardic or hypotensive:
                score += 10
                subscores['clinical_evaluation'] = 10
                feedback_parts.append(f"Partial dehydration vitals recorded: HR {hr_val} bpm, Sys BP {sys_val} mmHg")
            else:
                score += 5
                subscores['clinical_evaluation'] = 5
                feedback_parts.append(f"Evaluation created but vitals did not indicate dehydration (HR {hr_val}, Sys BP {sys_val})")
        except ValueError:
            score += 5
            subscores['clinical_evaluation'] = 5
            feedback_parts.append(f"Evaluation created but vitals were malformed: HR {eval_hr_str}, Sys BP {eval_sys_str}")
    else:
        subscores['clinical_evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented")

    # --- Criterion 3: Prescription Order (20 pts) ---
    presc_found = result.get('presc_found', False)
    presc_lines = result.get('presc_lines', 0)
    metro_lines = result.get('metronidazole_lines', 0)

    if presc_found:
        if metro_lines >= 1 and presc_lines >= 2:
            score += 20
            subscores['prescription'] = 20
            feedback_parts.append(f"Multi-drug prescription found containing Metronidazole ({presc_lines} total lines)")
        elif metro_lines >= 1:
            score += 15
            subscores['prescription'] = 15
            feedback_parts.append(f"Metronidazole prescribed, but missing accompanying hydration/symptom medication")
        elif presc_lines >= 2:
            score += 10
            subscores['prescription'] = 10
            feedback_parts.append(f"Multi-drug prescription found ({presc_lines} lines), but missing Metronidazole")
        else:
            score += 5
            subscores['prescription'] = 5
            feedback_parts.append(f"Prescription created but did not meet requirements")
    else:
        subscores['prescription'] = 0
        feedback_parts.append("MISSING: No medication prescription found")

    # --- Criterion 4: Laboratory Orders (20 pts) ---
    lab_count = result.get('lab_count', 0)
    if lab_count >= 1:
        score += 20
        subscores['laboratory'] = 20
        feedback_parts.append(f"Laboratory test(s) requested: {lab_count} orders")
    else:
        subscores['laboratory'] = 0
        feedback_parts.append("MISSING: No diagnostic lab tests requested")

    # --- Criterion 5: Follow-up Appointment (20 pts) ---
    appt_found = result.get('appt_found', False)
    appt_days_diff = result.get('appt_days_diff', 'null')

    if appt_found and appt_days_diff != 'null':
        try:
            days = int(appt_days_diff)
            if 1 <= days <= 3:
                score += 20
                subscores['appointment'] = 20
                feedback_parts.append(f"Follow-up appointment scheduled within timeframe ({days} days)")
            else:
                score += 10
                subscores['appointment'] = 10
                feedback_parts.append(f"Follow-up appointment scheduled, but outside 1-3 day window ({days} days)")
        except ValueError:
            subscores['appointment'] = 0
            feedback_parts.append(f"Appointment found but date formatting was unparsable: {appt_days_diff}")
    elif appt_found:
        score += 5
        subscores['appointment'] = 5
        feedback_parts.append("Appointment found but date difference could not be evaluated")
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