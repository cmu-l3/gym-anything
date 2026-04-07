#!/usr/bin/env python3
"""
Verifier for record_metabolic_syndrome_screening task.

This is a very_hard cross-module task testing clinical management of Metabolic Syndrome.

Scoring breakdown (100 points total):
  - 20 pts: 3 Active Diagnoses (E11, I10, E78) (7, 7, 6 pts)
  - 20 pts: Multi-drug Regimen (Metformin, AntiHTN, Statin) (20/12/6 pts based on count)
  - 20 pts: Metabolic lab orders (>=3 orders)
  - 20 pts: Lifestyle / dietary counseling record created
  - 20 pts: Follow-up appointment in 60-120 days
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_metabolic_syndrome_screening(traj, env_info, task_info):
    """Verify metabolic syndrome screening and management for patient Bonifacio Caput."""
    copy_from_env = env_info.get('copy_from_env')

    score = 0
    feedback_parts = []
    subscores = {}

    # --- Copy result JSON from VM ---
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/record_metabolic_syndrome_screening_result.json', local_path)
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
    if 'bonifacio' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient target. Expected Bonifacio Caput, got: {target_name}",
            "subscores": {}
        }

    # --- Criterion 1: Three Diagnoses (20 pts total) ---
    diag_score = 0
    diags_found = []
    
    # E11 (Diabetes)
    if result.get('e11_found'):
        if result.get('e11_active'):
            diag_score += 7
            diags_found.append("E11 (Active)")
        else:
            diag_score += 4
            diags_found.append("E11 (Inactive)")
            
    # I10 (Hypertension)
    if result.get('i10_found'):
        if result.get('i10_active'):
            diag_score += 7
            diags_found.append("I10 (Active)")
        else:
            diag_score += 4
            diags_found.append("I10 (Inactive)")

    # E78 (Dyslipidemia)
    if result.get('e78_found'):
        if result.get('e78_active'):
            diag_score += 6
            diags_found.append("E78 (Active)")
        else:
            diag_score += 3
            diags_found.append("E78 (Inactive)")

    score += diag_score
    subscores['diagnoses'] = diag_score
    if diags_found:
        feedback_parts.append(f"Diagnoses found: {', '.join(diags_found)}")
    else:
        feedback_parts.append("MISSING: No metabolic syndrome diagnoses (E11, I10, E78) documented")

    # --- Criterion 2: Multi-drug Regimen (20 pts) ---
    rx_classes = 0
    drugs_found = []
    
    if result.get('metformin_found'):
        rx_classes += 1
        drugs_found.append("Metformin")
    if result.get('antihtn_found'):
        rx_classes += 1
        drugs_found.append("Anti-HTN")
    if result.get('statin_found'):
        rx_classes += 1
        drugs_found.append("Statin")
        
    if rx_classes >= 3:
        score += 20
        subscores['prescriptions'] = 20
        feedback_parts.append(f"Complete multi-drug regimen prescribed ({', '.join(drugs_found)})")
    elif rx_classes == 2:
        score += 12
        subscores['prescriptions'] = 12
        feedback_parts.append(f"Partial regimen prescribed ({', '.join(drugs_found)}) - missing 1 class")
    elif rx_classes == 1:
        score += 6
        subscores['prescriptions'] = 6
        feedback_parts.append(f"Only 1 medication class prescribed ({drugs_found[0]})")
    else:
        subscores['prescriptions'] = 0
        feedback_parts.append("MISSING: No required metabolic medications prescribed")

    # --- Criterion 3: Lab Orders (20 pts) ---
    lab_count = result.get('new_lab_count', 0)
    try:
        lab_count = int(lab_count)
    except (ValueError, TypeError):
        lab_count = 0
        
    if lab_count >= 3:
        score += 20
        subscores['labs'] = 20
        feedback_parts.append(f"Metabolic lab panel ordered ({lab_count} tests)")
    elif lab_count == 2:
        score += 12
        subscores['labs'] = 12
        feedback_parts.append(f"Only 2 lab tests ordered - expected >= 3 for full metabolic panel")
    elif lab_count == 1:
        score += 6
        subscores['labs'] = 6
        feedback_parts.append(f"Only 1 lab test ordered - insufficient for metabolic screening")
    else:
        subscores['labs'] = 0
        feedback_parts.append("MISSING: No metabolic screening labs ordered")

    # --- Criterion 4: Lifestyle Counseling (20 pts) ---
    if result.get('lifestyle_found'):
        score += 20
        subscores['lifestyle'] = 20
        feedback_parts.append("Dietary/exercise counseling documented in lifestyle record")
    else:
        subscores['lifestyle'] = 0
        feedback_parts.append("MISSING: No lifestyle or dietary counseling record created")

    # --- Criterion 5: Follow-up Appointment (20 pts) ---
    appt_days = result.get('appointment_days_diff', -1)
    try:
        appt_days = int(appt_days)
    except (ValueError, TypeError):
        appt_days = -1

    if 60 <= appt_days <= 120:
        score += 20
        subscores['appointment'] = 20
        feedback_parts.append(f"Follow-up appointment scheduled optimally ({appt_days} days out)")
    elif 30 <= appt_days <= 180:
        score += 10
        subscores['appointment'] = 10
        feedback_parts.append(f"Follow-up appointment scheduled ({appt_days} days out) - optimal window is 60-120 days")
    elif appt_days >= 0:
        score += 5
        subscores['appointment'] = 5
        feedback_parts.append(f"Follow-up appointment scheduled but outside clinical window ({appt_days} days out)")
    else:
        subscores['appointment'] = 0
        feedback_parts.append("MISSING: No metabolic follow-up appointment scheduled")

    # --- Final Evaluation ---
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }