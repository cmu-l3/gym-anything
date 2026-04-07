#!/usr/bin/env python3
"""
Verifier for occupational_traumatic_brain_injury task.

This task requires managing a concussion protocol including diagnosis, 
precise GCS evaluation, safe prescribing (no NSAIDs), lab ordering, and follow-up.

Scoring breakdown (100 points total):
  - 20 pts: Concussion diagnosis (S06.x) for Bonifacio Caput
  - 20 pts: Evaluation with GCS (Eyes=3, Verbal=4, Motor=6) and Pain=6
  - 20 pts: Safe analgesia (Acetaminophen/Paracetamol) AND strictly NO NSAIDs
  - 20 pts: Bleeding lab order (CBC or Coagulation panel)
  - 20 pts: Return-to-Work follow-up appointment within 3-7 days

Pass threshold: score >= 80 AND no contraindicated drugs prescribed.
"""

import json
import logging
import os
import tempfile
from datetime import datetime

logger = logging.getLogger(__name__)


def verify_occupational_traumatic_brain_injury(traj, env_info, task_info):
    """Verify occupational TBI management protocol for patient Bonifacio Caput."""
    copy_from_env = env_info.get('copy_from_env')
    metadata = task_info.get('metadata', {})

    score = 0
    feedback_parts = []
    subscores = {}

    # Expected values
    exp_eyes = metadata.get('expected_gcs_eyes', 3)
    exp_verbal = metadata.get('expected_gcs_verbal', 4)
    exp_motor = metadata.get('expected_gcs_motor', 6)
    exp_pain = metadata.get('expected_pain', 6)
    safe_analgesics = [d.lower() for d in metadata.get('safe_analgesics', ["acetaminophen", "paracetamol"])]
    contraindicated = [d.lower() for d in metadata.get('contraindicated_nsaids', ["ibuprofen", "aspirin", "naproxen", "diclofenac", "ketorolac", "celecoxib", "meloxicam"])]
    min_days = metadata.get('followup_min_days', 3)
    max_days = metadata.get('followup_max_days', 7)

    # --- Copy result JSON from VM ---
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/occupational_traumatic_brain_injury_result.json', local_path)
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

    # --- Criterion 1: Concussion Diagnosis S06.x (20 pts) ---
    s06_found = result.get('s06_found', False)
    s06_active = result.get('s06_active', False)
    s06_code = result.get('s06_code', 'none')
    any_new_disease = result.get('any_new_disease_count', 0)
    try:
        any_new_disease = int(any_new_disease)
    except (ValueError, TypeError):
        any_new_disease = 0

    if s06_found and s06_active:
        score += 20
        subscores['concussion_diagnosis'] = 20
        feedback_parts.append(f"Concussion diagnosis documented: ICD-10 {s06_code} (active)")
    elif s06_found:
        score += 15
        subscores['concussion_diagnosis'] = 15
        feedback_parts.append(f"S06 Concussion found but not marked active (code: {s06_code})")
    elif any_new_disease > 0:
        score += 5
        subscores['concussion_diagnosis'] = 5
        feedback_parts.append("A diagnosis was added but not an S06.x concussion code")
    else:
        subscores['concussion_diagnosis'] = 0
        feedback_parts.append("MISSING: No concussion diagnosis (S06.x) found for Bonifacio")

    # --- Criterion 2: Clinical evaluation with GCS and Pain (20 pts) ---
    eval_found = result.get('evaluation_found', False)
    eval_eyes = result.get('evaluation_gcs_eyes', 'null')
    eval_verbal = result.get('evaluation_gcs_verbal', 'null')
    eval_motor = result.get('evaluation_gcs_motor', 'null')
    eval_pain = result.get('evaluation_pain', 'null')

    if eval_found:
        gcs_perfect = (str(eval_eyes) == str(exp_eyes) and 
                       str(eval_verbal) == str(exp_verbal) and 
                       str(eval_motor) == str(exp_motor))
        pain_perfect = (str(eval_pain) == str(exp_pain))
        
        if gcs_perfect and pain_perfect:
            score += 20
            subscores['clinical_evaluation'] = 20
            feedback_parts.append("Evaluation complete: exact GCS (3, 4, 6) and Pain (6) documented")
        elif gcs_perfect:
            score += 15
            subscores['clinical_evaluation'] = 15
            feedback_parts.append("Evaluation GCS is perfect, but pain score is missing or incorrect")
        else:
            score += 10
            subscores['clinical_evaluation'] = 10
            feedback_parts.append(f"Evaluation found but GCS/Pain values incorrect. Found Eyes:{eval_eyes}, Verbal:{eval_verbal}, Motor:{eval_motor}, Pain:{eval_pain}")
    else:
        subscores['clinical_evaluation'] = 0
        feedback_parts.append("MISSING: No clinical evaluation documented")

    # --- Criterion 3: Safe Analgesia vs Contraindicated NSAIDs (20 pts) ---
    presc_found = result.get('prescription_found', False)
    prescribed_drugs = result.get('prescribed_drugs', '').lower()
    
    has_safe_analgesic = any(safe in prescribed_drugs for safe in safe_analgesics)
    has_contraindicated = any(nsaid in prescribed_drugs for nsaid in contraindicated)
    
    if has_contraindicated:
        score += 0
        subscores['safe_analgesia'] = 0
        feedback_parts.append(f"CRITICAL SAFETY FAILURE: Prescribed contraindicated NSAID for head trauma ({prescribed_drugs})")
    elif has_safe_analgesic:
        score += 20
        subscores['safe_analgesia'] = 20
        feedback_parts.append(f"Safe analgesia prescribed: {prescribed_drugs}")
    elif presc_found:
        score += 5
        subscores['safe_analgesia'] = 5
        feedback_parts.append(f"Prescriptions found but no standard safe analgesic identified ({prescribed_drugs})")
    else:
        subscores['safe_analgesia'] = 0
        feedback_parts.append("MISSING: No medications prescribed")

    # --- Criterion 4: Baseline Bleeding Labs (20 pts) ---
    new_lab_count = result.get('new_lab_count', 0)
    new_lab_types = result.get('new_lab_types', '').upper()
    try:
        new_lab_count = int(new_lab_count)
    except (ValueError, TypeError):
        new_lab_count = 0

    has_bleeding_lab = "CBC" in new_lab_types or "COAG" in new_lab_types or "PROTHROMBIN" in new_lab_types

    if has_bleeding_lab:
        score += 20
        subscores['bleeding_labs'] = 20
        feedback_parts.append(f"Bleeding/Baseline labs ordered ({new_lab_types})")
    elif new_lab_count > 0:
        score += 10
        subscores['bleeding_labs'] = 10
        feedback_parts.append(f"Labs ordered ({new_lab_types}) but missing CBC or Coagulation panel")
    else:
        subscores['bleeding_labs'] = 0
        feedback_parts.append("MISSING: No laboratory orders found")

    # --- Criterion 5: RTW Follow-up Appointment (20 pts) ---
    appt_found = result.get('appointment_found', False)
    appt_date_str = result.get('appointment_date', 'null')
    task_start_str = result.get('task_start_date', '')

    if appt_found and appt_date_str != 'null' and task_start_str:
        try:
            # Parse dates
            task_start_date = datetime.strptime(task_start_str, "%Y-%m-%d").date()
            # Appointment date might contain time, so we split or parse prefix
            appt_date_only = appt_date_str.split(' ')[0]
            appt_date = datetime.strptime(appt_date_only, "%Y-%m-%d").date()
            
            days_diff = (appt_date - task_start_date).days
            
            if min_days <= days_diff <= max_days:
                score += 20
                subscores['follow_up'] = 20
                feedback_parts.append(f"Follow-up scheduled correctly {days_diff} days out ({appt_date_only})")
            else:
                score += 10
                subscores['follow_up'] = 10
                feedback_parts.append(f"Follow-up scheduled {days_diff} days out, but expected between {min_days} and {max_days} days")
        except Exception as e:
            score += 5
            subscores['follow_up'] = 5
            feedback_parts.append(f"Appointment found but could not parse dates correctly: {e}")
    else:
        subscores['follow_up'] = 0
        feedback_parts.append("MISSING: No follow-up appointment scheduled")

    # --- Final Evaluation ---
    passed = score >= 80 and not has_contraindicated

    if not passed and score >= 80:
        feedback_parts.append("FAILED: Score met threshold, but failed critical safety check (prescribed NSAIDs).")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }