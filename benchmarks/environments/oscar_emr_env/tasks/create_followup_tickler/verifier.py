#!/usr/bin/env python3
"""
Verifier for create_followup_tickler task.

Task: For Thomas Bergmann (DOB: January 19, 1960), write an encounter note
documenting chest pain / ECG changes / cardiology referral, AND create a
tickler reminder for cardiology referral follow-up.

Scoring (100 points total):
  - Criterion 1: Encounter note created (any content)                    — 25 pts
  - Criterion 2: Encounter note has clinical content about chest pain     — 25 pts
  - Criterion 3: Tickler/reminder created for this patient               — 25 pts
  - Criterion 4: Tickler mentions cardiology or referral follow-up        — 25 pts

Pass threshold: 70 points
Wrong-target guard: If data belongs to wrong patient, score = 0.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_create_followup_tickler(traj, env_info, task_info):
    """
    Verify that an encounter note and tickler were created for Thomas Bergmann.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    expected_fname = metadata.get('patient_fname', 'Thomas')
    expected_lname = metadata.get('patient_lname', 'Bergmann')

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/create_followup_tickler_result.json', tmp.name)
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

    new_notes = result.get('new_note_count', 0)
    new_ticklers = result.get('new_tickler_count', 0)

    # Criterion 1: Encounter note created (25 pts)
    try:
        if new_notes >= 1 and result.get('note_has_content', False):
            score += 25
            subscores['encounter_note_created'] = True
            feedback_parts.append("Encounter note created")
        elif new_notes >= 1:
            score += 15
            subscores['encounter_note_created'] = 'minimal_content'
            feedback_parts.append("Note created but content may be minimal")
        else:
            subscores['encounter_note_created'] = False
            feedback_parts.append("No encounter note found")
    except Exception as e:
        feedback_parts.append(f"Note creation check error: {e}")

    # Criterion 2: Encounter note has clinical content about chest pain / ECG / cardiology (25 pts)
    try:
        has_chest = result.get('note_has_chest_pain', False)
        has_ecg = result.get('note_has_ecg_mention', False)
        has_cardio = result.get('note_has_cardiology', False)
        clinical_signals = sum([has_chest, has_ecg, has_cardio])

        if clinical_signals >= 2:
            score += 25
            subscores['note_clinical_content'] = True
            feedback_parts.append(f"Note has relevant clinical content (chest pain={has_chest}, ECG={has_ecg}, cardiology={has_cardio})")
        elif clinical_signals == 1:
            score += 12
            subscores['note_clinical_content'] = 'partial'
            feedback_parts.append(f"Note has partial clinical content ({clinical_signals}/3 expected keywords)")
        elif new_notes >= 1:
            score += 5
            subscores['note_clinical_content'] = 'generic'
            feedback_parts.append("Note exists but expected clinical keywords not detected")
        else:
            subscores['note_clinical_content'] = False
            feedback_parts.append("No note with clinical content found")
    except Exception as e:
        feedback_parts.append(f"Note content check error: {e}")

    # Criterion 3: Tickler created (25 pts)
    try:
        if new_ticklers >= 1:
            score += 25
            subscores['tickler_created'] = True
            feedback_parts.append(f"Tickler/reminder created ({new_ticklers} new)")
        else:
            subscores['tickler_created'] = False
            feedback_parts.append("No tickler/reminder found")
    except Exception as e:
        feedback_parts.append(f"Tickler creation check error: {e}")

    # Criterion 4: Tickler has relevant content about cardiology referral (25 pts)
    try:
        has_cardio_t = result.get('tickler_has_cardiology', False)
        has_followup_t = result.get('tickler_has_followup', False)
        tickler_has_content = result.get('tickler_has_content', False)

        if new_ticklers >= 1 and (has_cardio_t or has_followup_t):
            score += 25
            subscores['tickler_relevant'] = True
            feedback_parts.append("Tickler has relevant follow-up content")
        elif new_ticklers >= 1 and tickler_has_content:
            score += 12
            subscores['tickler_relevant'] = 'generic'
            feedback_parts.append("Tickler created but expected keywords (cardiology/referral) not detected")
        else:
            subscores['tickler_relevant'] = False
            feedback_parts.append("Tickler without relevant content or not created")
    except Exception as e:
        feedback_parts.append(f"Tickler content check error: {e}")

    passed = score >= 70

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "subscores": subscores
    }
