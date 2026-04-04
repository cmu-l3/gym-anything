#!/usr/bin/env python3
"""
Verifier for inpatient_admission_workflow task.

Scoring (100 points):
- Inpatient/admission encounter type created: 20 pts
- At least 3 of 4 respiratory vitals recorded (temp, RR, SpO2, BP): 25 pts
- Two diagnoses including Pneumonia: 25 pts
- Two drug prescriptions (at least one antibiotic): 20 pts
- Admission note >= 150 chars: 10 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_inpatient_admission_workflow(traj, env_info, task_info):
    """
    Verify inpatient admission was completed for Valentina Torres (BAH000023).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    expected_identifier = metadata.get('patient_identifier', 'BAH000023')

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env('/tmp/inpatient_admission_workflow_result.json', temp_path)
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

        # Criterion 1: Inpatient encounter (20 pts)
        if result.get('has_inpatient_encounter'):
            score += 20
            subscores['inpatient_encounter'] = 20
            feedback_parts.append("Inpatient/admission encounter created")
        else:
            subscores['inpatient_encounter'] = 0
            types_found = result.get('encounter_types_found', [])
            if result.get('new_encounters', 0) > 0:
                feedback_parts.append(f"Encounter created but not inpatient type (found: {types_found[:3]})")
            else:
                feedback_parts.append("No new encounter created")

        # Criterion 2: Respiratory vitals (25 pts)
        vitals = result.get('vitals', {})
        vital_count = vitals.get('vital_count', 0)
        if vitals.get('vitals_adequate'):
            score += 25
            subscores['vitals'] = 25
            feedback_parts.append(f"Vitals recorded ({vital_count}/4 types: temp={vitals.get('has_temp')}, RR={vitals.get('has_rr')}, SpO2={vitals.get('has_spo2')}, BP={vitals.get('has_bp')})")
        elif vital_count >= 2:
            score += 12
            subscores['vitals'] = 12
            feedback_parts.append(f"Partial vitals ({vital_count}/4 types recorded)")
        elif vital_count >= 1:
            score += 5
            subscores['vitals'] = 5
            feedback_parts.append(f"Only {vital_count} vital type recorded")
        else:
            subscores['vitals'] = 0
            feedback_parts.append("No vitals recorded")

        # Criterion 3: Two diagnoses including Pneumonia (25 pts)
        diagnoses = result.get('diagnoses', {})
        if diagnoses.get('two_diagnoses'):
            score += 25
            subscores['diagnoses'] = 25
            feedback_parts.append("Two diagnoses including Pneumonia documented")
        elif diagnoses.get('has_pneumonia_dx'):
            score += 15
            subscores['diagnoses'] = 15
            feedback_parts.append("Pneumonia diagnosis documented (missing second diagnosis)")
        else:
            subscores['diagnoses'] = 0
            dx_found = diagnoses.get('diagnosis_lines', [])
            if dx_found:
                feedback_parts.append(f"Diagnoses found but no Pneumonia: {dx_found[:2]}")
            else:
                feedback_parts.append("No diagnoses documented")

        # Criterion 4: Two medications (20 pts)
        medications = result.get('medications', {})
        if medications.get('has_two_medications') and medications.get('has_antibiotic'):
            score += 20
            subscores['medications'] = 20
            feedback_parts.append(f"Two medications prescribed (including antibiotic): {medications.get('drug_names', [])[:3]}")
        elif medications.get('has_two_medications'):
            score += 12
            subscores['medications'] = 12
            feedback_parts.append(f"Two medications prescribed but no recognized antibiotic: {medications.get('drug_names', [])[:3]}")
        elif medications.get('new_orders', 0) >= 1:
            score += 5
            subscores['medications'] = 5
            feedback_parts.append(f"Only {medications.get('new_orders', 0)} medication(s) prescribed")
        else:
            subscores['medications'] = 0
            feedback_parts.append("No medications prescribed")

        # Criterion 5: Admission note (10 pts)
        note_info = result.get('admission_note', {})
        if note_info.get('has_admission_note'):
            score += 10
            subscores['admission_note'] = 10
            feedback_parts.append(f"Admission note written ({note_info.get('note_length', 0)} chars)")
        else:
            subscores['admission_note'] = 0
            feedback_parts.append("No admission note found (need >=150 char text observation)")

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
