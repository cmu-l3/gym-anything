#!/usr/bin/env python3
"""
Verifier for medication_review_and_allergy task.

Task: For Fatima Al-Hassan (DOB: August 9, 1978):
  1. Discontinue/archive the incorrectly entered Amiodarone prescription
  2. Add an ASA allergy (reaction: GI upset, severity: Moderate)
  3. Prescribe Metformin 500mg BID

Scoring (100 points total):
  - Criterion 1: Amiodarone prescription discontinued/archived             — 30 pts
  - Criterion 2: ASA allergy added (active in chart)                       — 30 pts
  - Criterion 3: Metformin prescription added and active                   — 30 pts
  - Criterion 4: Correct Metformin dose (500mg)                            — 10 pts

Pass threshold: 70 points
Wrong-target guard: If data belongs to wrong patient, score = 0.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_medication_review_and_allergy(traj, env_info, task_info):
    """
    Verify medication reconciliation and allergy update for Fatima Al-Hassan.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    expected_fname = metadata.get('patient_fname', 'Fatima')
    expected_lname = metadata.get('patient_lname', 'Al-Hassan')

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/medication_review_and_allergy_result.json', tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    # Wrong-target guard
    if result.get('patient_fname') != expected_fname or result.get('patient_lname') != expected_lname:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Wrong target: expected {expected_fname} {expected_lname}"
        }

    # Criterion 1: Amiodarone archived/discontinued (30 pts)
    try:
        amiodarone_archived = result.get('amiodarone_archived', None)
        amiodarone_found = result.get('amiodarone_found_in_db', False)

        if amiodarone_archived is True:
            score += 30
            subscores['amiodarone_discontinued'] = True
            feedback_parts.append("Amiodarone correctly archived/discontinued")
        elif not amiodarone_found:
            # If Amiodarone was deleted entirely from the DB, that also counts
            score += 30
            subscores['amiodarone_discontinued'] = 'deleted'
            feedback_parts.append("Amiodarone removed from medication list")
        elif amiodarone_archived is False:
            subscores['amiodarone_discontinued'] = False
            feedback_parts.append("Amiodarone still active in chart — not discontinued")
        else:
            subscores['amiodarone_discontinued'] = False
            feedback_parts.append("Could not determine Amiodarone status")
    except Exception as e:
        feedback_parts.append(f"Amiodarone check error: {e}")

    # Criterion 2: ASA allergy added (30 pts)
    try:
        if result.get('asa_allergy_active', False):
            score += 30
            subscores['asa_allergy'] = True
            severity_note = " (Moderate severity confirmed)" if result.get('asa_severity_moderate') else ""
            feedback_parts.append(f"ASA allergy added and active{severity_note}")
        elif result.get('asa_allergy_found', False):
            score += 15
            subscores['asa_allergy'] = 'found_not_active'
            feedback_parts.append("ASA allergy found but may be archived or inactive")
        elif result.get('current_active_allergies', 0) >= 1:
            # An allergy was added but may not be named ASA
            score += 15
            subscores['asa_allergy'] = 'different_name'
            feedback_parts.append("Allergy added but 'ASA'/'Acetylsalicylic' not detected by name")
        else:
            subscores['asa_allergy'] = False
            feedback_parts.append("ASA allergy not found in chart")
    except Exception as e:
        feedback_parts.append(f"ASA allergy check error: {e}")

    # Criterion 3: Metformin active prescription (30 pts)
    try:
        if result.get('metformin_active', False):
            score += 30
            subscores['metformin_prescribed'] = True
            feedback_parts.append("Metformin prescription added and active")
        elif result.get('metformin_found', False):
            score += 15
            subscores['metformin_prescribed'] = 'found_archived'
            feedback_parts.append("Metformin found but appears archived")
        elif result.get('current_active_drugs', 0) > result.get('initial_drug_count', 0):
            # Something new was prescribed but not Metformin
            score += 10
            subscores['metformin_prescribed'] = 'different_drug'
            feedback_parts.append("Medication added but Metformin not confirmed by name")
        else:
            subscores['metformin_prescribed'] = False
            feedback_parts.append("Metformin not found as active prescription")
    except Exception as e:
        feedback_parts.append(f"Metformin check error: {e}")

    # Criterion 4: Correct Metformin dose (10 pts)
    try:
        if result.get('metformin_dose_500mg', False):
            score += 10
            subscores['metformin_dose'] = True
            feedback_parts.append("Metformin dose 500mg confirmed")
        elif result.get('metformin_active', False):
            feedback_parts.append("Metformin active but 500mg dose not confirmed")
            subscores['metformin_dose'] = False
        else:
            subscores['metformin_dose'] = False
    except Exception as e:
        feedback_parts.append(f"Metformin dose check error: {e}")

    passed = score >= 70

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "subscores": subscores
    }
