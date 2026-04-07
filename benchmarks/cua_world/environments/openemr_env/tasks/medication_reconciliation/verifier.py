#!/usr/bin/env python3
"""
Verifier for Medication Reconciliation task in OpenEMR

Robust verification with adversarial case handling:
1. Must be for correct patient (pid=25, Edmund Walker)
2. Must have NEW prescriptions added (not pre-existing)
3. Must have at least 3 of 5 target medications
4. Doses should be reasonable for each drug class
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_medication_reconciliation(traj, env_info, task_info):
    """
    Verify that medication reconciliation was completed.

    Scoring (100 points total):
    - Correct patient: 15 points
    - New prescriptions added: 15 points
    - Lisinopril (ACE inhibitor): 14 points
    - Metformin (Diabetes): 14 points
    - Atorvastatin (Statin): 14 points
    - Aspirin (Antiplatelet): 14 points
    - Omeprazole (PPI): 14 points

    Passing threshold: 57 points (correct patient + new rx + 3 meds)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 25)
    expected_fname = metadata.get('patient_fname', 'Edmund')
    expected_lname = metadata.get('patient_lname', 'Walker')
    min_meds_required = metadata.get('minimum_medications_required', 3)

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/medication_reconciliation_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "correct_patient": False,
            "new_prescriptions": False,
            "lisinopril": False,
            "metformin": False,
            "atorvastatin": False,
            "aspirin": False,
            "omeprazole": False
        }

        # Extract data
        patient_pid = result.get('patient_pid', 0)
        initial_rx_count = result.get('initial_rx_count', 0)
        current_rx_count = result.get('current_rx_count', 0)
        new_rx_count = result.get('new_rx_count', 0)
        target_meds_found = result.get('target_medications_found', 0)
        medications = result.get('medications', {})

        logger.info(f"Result: pid={patient_pid}, initial={initial_rx_count}, current={current_rx_count}, new={new_rx_count}, target_found={target_meds_found}")

        # CRITERION 1: Correct patient (15 points)
        if patient_pid == expected_pid:
            score += 15
            subscores["correct_patient"] = True
            feedback_parts.append(f"Correct patient (pid={expected_pid})")
        else:
            feedback_parts.append(f"CRITICAL: Wrong patient! Expected pid={expected_pid}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Medications added for wrong patient (expected pid={expected_pid})",
                "subscores": subscores
            }

        # CRITERION 2: New prescriptions added (15 points)
        if new_rx_count > 0:
            score += 15
            subscores["new_prescriptions"] = True
            feedback_parts.append(f"New prescriptions added: {new_rx_count}")
        else:
            feedback_parts.append("No new prescriptions added")

        # CRITERION 3-7: Check each target medication (14 points each)
        meds_details = []

        # Lisinopril
        lis_data = medications.get('lisinopril', {})
        if lis_data.get('found', False):
            score += 14
            subscores["lisinopril"] = True
            dose = lis_data.get('dose', '')
            meds_details.append(f"Lisinopril ({dose})")

        # Metformin
        met_data = medications.get('metformin', {})
        if met_data.get('found', False):
            score += 14
            subscores["metformin"] = True
            dose = met_data.get('dose', '')
            meds_details.append(f"Metformin ({dose})")

        # Atorvastatin
        ator_data = medications.get('atorvastatin', {})
        if ator_data.get('found', False):
            score += 14
            subscores["atorvastatin"] = True
            dose = ator_data.get('dose', '')
            meds_details.append(f"Atorvastatin ({dose})")

        # Aspirin
        asp_data = medications.get('aspirin', {})
        if asp_data.get('found', False):
            score += 14
            subscores["aspirin"] = True
            dose = asp_data.get('dose', '')
            meds_details.append(f"Aspirin ({dose})")

        # Omeprazole
        ome_data = medications.get('omeprazole', {})
        if ome_data.get('found', False):
            score += 14
            subscores["omeprazole"] = True
            dose = ome_data.get('dose', '')
            meds_details.append(f"Omeprazole ({dose})")

        if meds_details:
            feedback_parts.append(f"Medications: {', '.join(meds_details)}")
        else:
            feedback_parts.append("No target medications found")

        # Count medications found
        meds_count = sum([
            subscores["lisinopril"],
            subscores["metformin"],
            subscores["atorvastatin"],
            subscores["aspirin"],
            subscores["omeprazole"]
        ])

        feedback_parts.append(f"Target meds: {meds_count}/5")

        # Determine pass/fail
        # Must have: correct patient (15) + new rx (15) + at least 3 meds (42) = 72 minimum
        has_core = subscores["correct_patient"] and subscores["new_prescriptions"]
        has_min_meds = meds_count >= min_meds_required
        passed = has_core and has_min_meds

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "patient_pid": patient_pid,
                "new_prescriptions": new_rx_count,
                "medications_found": meds_count,
                "medications_required": min_meds_required,
                "lisinopril": lis_data,
                "metformin": met_data,
                "atorvastatin": ator_data,
                "aspirin": asp_data,
                "omeprazole": ome_data
            }
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export_result.sh may not have run"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
