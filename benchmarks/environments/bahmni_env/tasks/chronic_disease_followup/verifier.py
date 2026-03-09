#!/usr/bin/env python3
"""
Verifier for chronic_disease_followup task.

Scoring (100 points):
- Vitals recorded (systolic BP + diastolic BP + pulse + weight/temp): 25 pts
- Two coded diagnoses (T2DM + Hypertension): 25 pts
- Two drug prescriptions (one DM drug + one HTN drug): 25 pts
- Clinical note of sufficient length (>=100 chars): 15 pts
- Correct patient (BAH000022): 10 pts (wrong target = score 0 immediately)

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_chronic_disease_followup(traj, env_info, task_info):
    """
    Verify chronic disease follow-up consultation was completed for Mohammed Al-Rashidi (BAH000022).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    expected_identifier = metadata.get('patient_identifier', 'BAH000022')

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env('/tmp/chronic_disease_followup_result.json', temp_path)
            with open(temp_path, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_path):
                os.unlink(temp_path)

        score = 0
        feedback_parts = []
        subscores = {}

        # CRITICAL CHECK: Wrong patient = immediate score 0
        actual_identifier = result.get('patient_identifier', '')
        if actual_identifier != expected_identifier:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"CRITICAL: Wrong patient! Expected {expected_identifier}, got {actual_identifier}",
                "subscores": {}
            }

        # Criterion 1: Vitals recorded (25 pts)
        vitals = result.get('vitals', {})
        if vitals.get('vitals_complete'):
            score += 25
            subscores['vitals'] = 25
            feedback_parts.append("Vitals complete (BP, pulse, weight/temp)")
        elif vitals.get('has_systolic') and vitals.get('has_diastolic'):
            score += 15
            subscores['vitals'] = 15
            feedback_parts.append("Partial vitals (BP recorded, missing pulse/weight)")
        elif vitals.get('has_systolic') or vitals.get('has_diastolic'):
            score += 5
            subscores['vitals'] = 5
            feedback_parts.append("Minimal vitals (only one BP component)")
        else:
            subscores['vitals'] = 0
            feedback_parts.append("No vitals recorded")

        # Criterion 2: Two diagnoses (T2DM + HTN) (25 pts)
        diagnoses = result.get('diagnoses', {})
        if diagnoses.get('two_diagnoses'):
            score += 25
            subscores['diagnoses'] = 25
            feedback_parts.append("Both diagnoses documented (T2DM + HTN)")
        elif diagnoses.get('has_diabetes_dx') or diagnoses.get('has_htn_dx'):
            score += 10
            subscores['diagnoses'] = 10
            dx_found = []
            if diagnoses.get('has_diabetes_dx'):
                dx_found.append('T2DM')
            if diagnoses.get('has_htn_dx'):
                dx_found.append('HTN')
            feedback_parts.append(f"Only one diagnosis found: {', '.join(dx_found)}")
        else:
            subscores['diagnoses'] = 0
            feedback_parts.append("No diagnoses documented")

        # Criterion 3: Two drug prescriptions (one DM + one HTN) (25 pts)
        medications = result.get('medications', {})
        if medications.get('two_drugs'):
            score += 25
            subscores['medications'] = 25
            feedback_parts.append("Two medication classes prescribed (DM + HTN drugs)")
        elif medications.get('has_dm_drug') or medications.get('has_htn_drug'):
            score += 10
            subscores['medications'] = 10
            drugs_found = []
            if medications.get('has_dm_drug'):
                drugs_found.append('DM drug')
            if medications.get('has_htn_drug'):
                drugs_found.append('HTN drug')
            feedback_parts.append(f"Only partial medications: {', '.join(drugs_found)}")
        else:
            subscores['medications'] = 0
            drugs_listed = medications.get('drug_names_found', [])
            feedback_parts.append(f"No recognized medications prescribed. Found: {drugs_listed[:3]}")

        # Criterion 4: Clinical note (15 pts)
        note_info = result.get('clinical_note', {})
        if note_info.get('has_clinical_note'):
            score += 15
            subscores['clinical_note'] = 15
            feedback_parts.append(f"Clinical note documented ({note_info.get('note_length', 0)} chars)")
        else:
            subscores['clinical_note'] = 0
            feedback_parts.append("No clinical note found (need >=100 char text observation)")

        # Bonus: New encounter created (signals proper workflow)
        if result.get('new_encounters', 0) > 0:
            feedback_parts.append(f"New encounter(s) created: {result.get('new_encounters')}")
        else:
            feedback_parts.append("Warning: No new encounters detected — data may be on pre-existing encounter")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export script may have failed"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file is not valid JSON: {str(e)}"
        }
    except Exception as e:
        logger.exception("Unexpected error in verifier")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verifier error: {str(e)}"
        }
