#!/usr/bin/env python3
"""
Verifier for medication_allergy_reconciliation task.

Scoring (100 points):
- Penicillin allergy documented in patient allergy list: 30 pts
- Penicillin V drug order discontinued/voided: 20 pts
- Safe non-penicillin alternative antibiotic prescribed: 30 pts
- Clinical note documenting allergy/medication changes (>=100 chars): 20 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_medication_allergy_reconciliation(traj, env_info, task_info):
    """
    Verify medication allergy reconciliation was performed for Aisha Abdullahi (BAH000008).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    expected_identifier = metadata.get('patient_identifier', 'BAH000008')

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env('/tmp/medication_allergy_reconciliation_result.json', temp_path)
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

        # Criterion 1: Penicillin allergy documented (30 pts)
        if result.get('penicillin_allergy_documented'):
            score += 30
            subscores['allergy_documentation'] = 30
            allergy_details = result.get('allergy_details', [])
            pen_allergy = next((a for a in allergy_details if 'penicillin' in a.get('allergen', '').lower()), {})
            severity = pen_allergy.get('severity', 'not specified')
            feedback_parts.append(f"Penicillin allergy documented (severity: {severity})")
        else:
            subscores['allergy_documentation'] = 0
            new_allergies = result.get('new_allergies', 0)
            if new_allergies > 0:
                feedback_parts.append(f"Allergy recorded but not Penicillin ({new_allergies} new allergy entries found)")
            else:
                feedback_parts.append("No Penicillin allergy documented in patient allergy list")

        # Criterion 2: Penicillin V order discontinued (20 pts)
        if result.get('penicillin_order_discontinued'):
            score += 20
            subscores['penicillin_discontinuation'] = 20
            feedback_parts.append("Penicillin V order discontinued/voided")
        else:
            subscores['penicillin_discontinuation'] = 0
            feedback_parts.append("Penicillin V order still active (not discontinued/voided)")

        # Criterion 3: Safe alternative antibiotic prescribed (30 pts)
        if result.get('has_safe_alternative_antibiotic'):
            score += 30
            subscores['safe_alternative'] = 30
            alts = result.get('new_antibiotic_orders', [])
            feedback_parts.append(f"Safe alternative antibiotic prescribed: {alts[:2]}")
        else:
            subscores['safe_alternative'] = 0
            feedback_parts.append("No safe non-penicillin antibiotic prescribed")

        # Criterion 4: Clinical note (20 pts)
        note_info = result.get('clinical_note', {})
        if note_info.get('has_clinical_note'):
            score += 20
            subscores['clinical_note'] = 20
            feedback_parts.append(f"Clinical note documented ({note_info.get('note_length', 0)} chars)")
        else:
            subscores['clinical_note'] = 0
            feedback_parts.append("No clinical note found (need >=100 char text observation)")

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
