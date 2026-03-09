#!/usr/bin/env python3
"""
Verifier for complete_patient_profile task.

Task: Set up Jean-Pierre Bouchard's cumulative patient profile by adding
two allergies (Penicillin/Severe and Sulfa/Moderate) and two medications
(Metformin 500mg BID and Ramipril 10mg OD).

Scoring (100 points total):
  - Criterion 1: Penicillin allergy added                      — 25 pts
    (Bonus: +5 if severity correctly set to Severe)
  - Criterion 2: Sulfa/Sulfonamide allergy added               — 20 pts
  - Criterion 3: Metformin prescription added (active)         — 25 pts
  - Criterion 4: Ramipril prescription added (active)          — 25 pts

Pass threshold: 70 points
Wrong-target guard: If data belongs to wrong patient, score = 0.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_complete_patient_profile(traj, env_info, task_info):
    """
    Verify that Jean-Pierre Bouchard's patient profile was completed with
    required allergies and medications.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    expected_fname = metadata.get('patient_fname', 'Jean-Pierre')
    expected_lname = metadata.get('patient_lname', 'Bouchard')

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/complete_patient_profile_result.json', tmp.name)
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

    new_allergies = result.get('new_allergy_count', 0)
    new_drugs = result.get('new_drug_count', 0)

    # Criterion 1: Penicillin allergy added (25 pts, +5 bonus for Severe severity)
    try:
        if result.get('has_penicillin_allergy', False):
            pts = 25
            if result.get('penicillin_severity_severe', False):
                pts = 30
                feedback_parts.append("Penicillin allergy added (Severe severity — correct)")
            else:
                feedback_parts.append("Penicillin allergy added (severity may differ from Severe)")
            score += pts
            subscores['penicillin_allergy'] = True
        elif new_allergies >= 1:
            # Some allergies added but Penicillin not detected — may be named differently
            score += 10
            subscores['penicillin_allergy'] = 'undetected_name'
            feedback_parts.append("Allergies added but Penicillin not confirmed by name")
        else:
            subscores['penicillin_allergy'] = False
            feedback_parts.append("Penicillin allergy not found")
    except Exception as e:
        feedback_parts.append(f"Penicillin check error: {e}")

    # Criterion 2: Sulfa allergy added (20 pts)
    try:
        if result.get('has_sulfa_allergy', False):
            score += 20
            subscores['sulfa_allergy'] = True
            feedback_parts.append("Sulfonamide/Sulfa allergy added")
        elif new_allergies >= 2:
            # 2+ allergies added but sulfa not detected by name
            score += 8
            subscores['sulfa_allergy'] = 'undetected_name'
            feedback_parts.append("2 allergies present but Sulfa not confirmed by name")
        else:
            subscores['sulfa_allergy'] = False
            feedback_parts.append("Sulfa/Sulfonamide allergy not found")
    except Exception as e:
        feedback_parts.append(f"Sulfa check error: {e}")

    # Criterion 3: Metformin prescription (25 pts)
    try:
        if result.get('has_metformin', False):
            score += 25
            subscores['metformin'] = True
            dose_note = " (500mg confirmed)" if result.get('metformin_dose_500mg') else ""
            feedback_parts.append(f"Metformin prescription added{dose_note}")
        elif new_drugs >= 1:
            score += 10
            subscores['metformin'] = 'undetected_name'
            feedback_parts.append("Medications added but Metformin not confirmed by name")
        else:
            subscores['metformin'] = False
            feedback_parts.append("Metformin prescription not found")
    except Exception as e:
        feedback_parts.append(f"Metformin check error: {e}")

    # Criterion 4: Ramipril prescription (25 pts)
    try:
        if result.get('has_ramipril', False):
            score += 25
            subscores['ramipril'] = True
            dose_note = " (10mg confirmed)" if result.get('ramipril_dose_10mg') else ""
            feedback_parts.append(f"Ramipril prescription added{dose_note}")
        elif new_drugs >= 2:
            score += 10
            subscores['ramipril'] = 'undetected_name'
            feedback_parts.append("2 medications present but Ramipril not confirmed by name")
        else:
            subscores['ramipril'] = False
            feedback_parts.append("Ramipril prescription not found")
    except Exception as e:
        feedback_parts.append(f"Ramipril check error: {e}")

    passed = score >= 70

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "subscores": subscores
    }
