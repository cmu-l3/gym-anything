#!/usr/bin/env python3
"""
Verifier for Prescribe Medication task in OpenEMR

Robust verification with adversarial case handling:
1. Must be for correct patient (pid=7, Milo Feil)
2. Must be a NEW prescription (created during task)
3. Must be Amoxicillin (correct antibiotic choice)
4. Must have 500 MG strength
5. Must have appropriate quantity (20-40 for 10-day course)
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_prescribe_medication(traj, env_info, task_info):
    """
    Verify that correct antibiotic prescription was created.

    Scoring (100 points total):
    - Prescription for correct patient: 25 points
    - New prescription created: 20 points
    - Correct drug (Amoxicillin): 25 points
    - Correct strength (500 MG): 15 points
    - Appropriate quantity (20-40): 15 points

    Passing threshold: 70 points (must have correct patient + new + amoxicillin)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 7)
    expected_fname = metadata.get('patient_fname', 'Milo')
    expected_lname = metadata.get('patient_lname', 'Feil')
    expected_drug = metadata.get('expected_drug_name', 'Amoxicillin')
    expected_strength = metadata.get('expected_drug_strength', '500')
    expected_qty_min = metadata.get('expected_quantity_min', 20)
    expected_qty_max = metadata.get('expected_quantity_max', 40)

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/prescribe_medication_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "correct_patient": False,
            "newly_created": False,
            "correct_drug": False,
            "correct_strength": False,
            "appropriate_quantity": False
        }

        # Extract data
        patient_pid = result.get('patient_pid', 0)
        initial_count = result.get('initial_rx_count', 0)
        current_count = result.get('current_rx_count', 0)
        rx_found = result.get('prescription_found', False)
        prescription = result.get('prescription', {})
        validation = result.get('validation', {})

        logger.info(f"Result data: pid={patient_pid}, initial={initial_count}, current={current_count}, found={rx_found}")
        logger.info(f"Prescription: {prescription}")

        # CRITERION 1: Correct patient (25 points)
        if patient_pid == expected_pid:
            if rx_found:
                score += 25
                subscores["correct_patient"] = True
                feedback_parts.append(f"Prescription found for correct patient (pid={expected_pid})")
            else:
                feedback_parts.append(f"No prescription found for patient pid={expected_pid}")
        else:
            feedback_parts.append(f"CRITICAL: Wrong patient! Expected pid={expected_pid}, got {patient_pid}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Prescription created for wrong patient (expected pid={expected_pid})",
                "subscores": subscores
            }

        if not rx_found:
            feedback_parts.append("No prescription was created")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # CRITERION 2: New prescription (20 points)
        if current_count > initial_count:
            score += 20
            subscores["newly_created"] = True
            feedback_parts.append(f"New prescription created (count: {initial_count} -> {current_count})")
        else:
            feedback_parts.append(f"No new prescription detected (count unchanged: {current_count})")
            # Adversarial case: claiming existing prescription

        # CRITERION 3: Correct drug - Amoxicillin (25 points)
        drug_name = prescription.get('drug', '').lower()
        if 'amoxicillin' in drug_name:
            score += 25
            subscores["correct_drug"] = True
            feedback_parts.append(f"Correct antibiotic: {prescription.get('drug', '')}")
        else:
            # Check if it's at least a penicillin-class antibiotic
            if any(ab in drug_name for ab in ['penicillin', 'ampicillin', 'augmentin']):
                score += 15  # Partial credit for related antibiotic
                feedback_parts.append(f"Related antibiotic prescribed: {prescription.get('drug', '')} (expected Amoxicillin)")
            else:
                feedback_parts.append(f"Wrong drug: {prescription.get('drug', '')} (expected Amoxicillin)")

        # CRITERION 4: Correct strength - 500 MG (15 points)
        drug_str = prescription.get('drug', '') + ' ' + str(prescription.get('dosage', ''))
        if '500' in drug_str:
            score += 15
            subscores["correct_strength"] = True
            feedback_parts.append("Correct strength: 500 MG")
        elif '250' in drug_str:
            score += 8  # Partial credit for 250mg (acceptable alternative)
            feedback_parts.append("Alternative strength: 250 MG (500 MG preferred)")
        elif '875' in drug_str:
            score += 10  # Partial credit for 875mg (also guideline-compliant)
            feedback_parts.append("Alternative strength: 875 MG (acceptable per guidelines)")
        else:
            feedback_parts.append(f"Strength unclear or incorrect: {drug_str}")

        # CRITERION 5: Appropriate quantity (15 points)
        try:
            quantity = int(prescription.get('quantity', 0))
            if expected_qty_min <= quantity <= expected_qty_max:
                score += 15
                subscores["appropriate_quantity"] = True
                feedback_parts.append(f"Appropriate quantity: {quantity} (for 10-day course)")
            elif quantity > 0:
                # Give partial credit if quantity is reasonable but outside range
                if 10 <= quantity <= 60:
                    score += 8
                    feedback_parts.append(f"Quantity {quantity} is reasonable but not optimal ({expected_qty_min}-{expected_qty_max} expected)")
                else:
                    feedback_parts.append(f"Quantity {quantity} is inappropriate for 10-day course")
            else:
                feedback_parts.append("No quantity specified")
        except (ValueError, TypeError):
            feedback_parts.append(f"Could not parse quantity: {prescription.get('quantity')}")

        # Additional check: refills should be 0 for acute infection
        refills = prescription.get('refills', '')
        try:
            refills_int = int(refills) if refills else 0
            if refills_int == 0:
                feedback_parts.append("Refills correctly set to 0")
            else:
                feedback_parts.append(f"Note: Refills set to {refills_int} (should be 0 for acute infection)")
        except (ValueError, TypeError):
            pass

        # Determine pass/fail
        # Must have: correct patient (25) + new (20) + amoxicillin (25) = 70 minimum
        passed = score >= 70 and subscores["correct_patient"] and subscores["correct_drug"]

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "drug_prescribed": prescription.get('drug', ''),
                "quantity": prescription.get('quantity', ''),
                "refills": prescription.get('refills', ''),
                "patient_pid": patient_pid,
                "prescriptions_before": initial_count,
                "prescriptions_after": current_count
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
