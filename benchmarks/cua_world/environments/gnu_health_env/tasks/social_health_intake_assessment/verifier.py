#!/usr/bin/env python3
"""
Verifier for social_health_intake_assessment task.

Scoring breakdown (100 points total):
  - 20 pts: Socioeconomic data updated (education=University, occupation=Engineer/technical)
  - 20 pts: Lifestyle record created (physical activity, tobacco status)
  - 20 pts: Family history entry added (cardiovascular disease, ICD-10 I2x family)
  - 20 pts: Phone contact added to party record
  - 20 pts: Preventive care appointment within 150-200 days

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_social_health_intake_assessment(traj, env_info, task_info):
    """Verify comprehensive SDOH intake assessment for Matt Zenon Betz."""
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
        copy_from_env('/tmp/social_health_intake_assessment_result.json', local_path)
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
            "feedback": "CRITICAL: Matt Zenon Betz not found — setup may have failed.",
            "subscores": {}
        }

    target_name = result.get('target_patient_name', '')
    if 'matt' not in target_name.lower() and 'betz' not in target_name.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong patient. Expected Matt Zenon Betz, got: {target_name}",
            "subscores": {}
        }

    # --- Criterion 1: Socioeconomic data (20 pts) ---
    education_set = result.get('education_set', False)
    education_is_university = result.get('education_is_university', False)
    education_value = result.get('education_value', '')
    occupation_set = result.get('occupation_set', False)
    occupation_name = result.get('occupation_name', '')

    if education_set and occupation_set:
        # Full points if both are set, and university/engineer terms found
        if education_is_university and ('engineer' in occupation_name.lower() or
                                         'technical' in occupation_name.lower() or
                                         'tech' in occupation_name.lower() or
                                         'it' in occupation_name.lower()):
            score += 20
            subscores['socioeconomic'] = 20
            feedback_parts.append(f"Socioeconomics complete: Education={education_value}, Occupation={occupation_name}")
        else:
            score += 14
            subscores['socioeconomic'] = 14
            feedback_parts.append(f"Socioeconomics partially correct: Education='{education_value}' (university={education_is_university}), Occupation='{occupation_name}'")
    elif education_set or occupation_set:
        score += 8
        subscores['socioeconomic'] = 8
        feedback_parts.append(f"Only partial socioeconomics completed (education_set={education_set}, occupation_set={occupation_set})")
    else:
        subscores['socioeconomic'] = 0
        feedback_parts.append("MISSING: Education and Occupation not updated for Matt Zenon Betz")

    # --- Criterion 2: Lifestyle record (20 pts) ---
    lifestyle_found = result.get('lifestyle_found', False)
    lifestyle_active = result.get('lifestyle_active', False)
    lifestyle_non_smoker = result.get('lifestyle_non_smoker', False)

    if lifestyle_found and lifestyle_active and lifestyle_non_smoker:
        score += 20
        subscores['lifestyle'] = 20
        feedback_parts.append("Lifestyle record complete (active exercise, non-smoker)")
    elif lifestyle_found and (lifestyle_active or lifestyle_non_smoker):
        score += 13
        subscores['lifestyle'] = 13
        feedback_parts.append(f"Lifestyle record created but incomplete (active={lifestyle_active}, non_smoker={lifestyle_non_smoker})")
    elif lifestyle_found:
        score += 8
        subscores['lifestyle'] = 8
        feedback_parts.append("Lifestyle record created but activity/tobacco status not confirmed")
    else:
        subscores['lifestyle'] = 0
        feedback_parts.append("MISSING: No lifestyle record created for Matt Zenon Betz")

    # --- Criterion 3: Family history (20 pts) ---
    family_cardio_found = result.get('family_cardio_found', False)
    family_code = result.get('family_disease_code', 'none')
    any_family_new = result.get('any_new_family_disease', 0)

    if family_cardio_found:
        score += 20
        subscores['family_history'] = 20
        feedback_parts.append(f"Cardiovascular family history added (ICD-10: {family_code})")
    elif any_family_new and int(any_family_new) > 0:
        score += 12
        subscores['family_history'] = 12
        feedback_parts.append(f"Family history added but not a cardiovascular/coronary code (got: {family_code})")
    else:
        subscores['family_history'] = 0
        feedback_parts.append("MISSING: No family history added for Matt Zenon Betz (should be cardiovascular disease)")

    # --- Criterion 4: Phone contact (20 pts) ---
    phone_found = result.get('phone_contact_found', False)
    any_contact = result.get('any_new_contact_count', 0)
    contact_value = result.get('contact_value', '')

    if phone_found:
        score += 20
        subscores['phone_contact'] = 20
        feedback_parts.append(f"Mobile/phone contact added ({contact_value})")
    elif any_contact and int(any_contact) > 0:
        score += 14
        subscores['phone_contact'] = 14
        feedback_parts.append(f"A contact was added (not confirmed as phone type — may be email or other)")
    else:
        subscores['phone_contact'] = 0
        feedback_parts.append("MISSING: No phone contact added for Matt Zenon Betz")

    # --- Criterion 5: Preventive care appointment (20 pts) ---
    appt_in_range = result.get('preventive_appt_in_range', False)
    appt_date = result.get('preventive_appt_date', 'none')
    any_new_appts = result.get('any_new_appt_count', 0)
    win_min = result.get('preventive_window_min', '')
    win_max = result.get('preventive_window_max', '')

    if appt_in_range:
        score += 20
        subscores['preventive_appointment'] = 20
        feedback_parts.append(f"Preventive appointment scheduled for {appt_date} (150-200 day window)")
    elif any_new_appts and int(any_new_appts) > 0:
        score += 8
        subscores['preventive_appointment'] = 8
        feedback_parts.append(f"An appointment was scheduled but NOT in 150-200 day window ({win_min} to {win_max})")
    else:
        subscores['preventive_appointment'] = 0
        feedback_parts.append(f"MISSING: No preventive care appointment in 150-200 day window")

    # --- Final result ---
    passed = score >= 70
    feedback = " | ".join(feedback_parts) if feedback_parts else "No criteria met"

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "subscores": subscores,
        "target_patient": target_name
    }
