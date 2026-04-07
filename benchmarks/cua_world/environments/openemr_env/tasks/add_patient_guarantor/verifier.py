#!/usr/bin/env python3
"""
Verifier for Add Patient Guarantor task in OpenEMR

Verifies that guarantor information was correctly added to a minor patient's account.

Expected guarantor:
- Name: Maria Gusikowski
- Relationship: Parent
- Address: 661 Nikolaus Well, Northampton, MA 01060
- Phone: (413) 555-0198

Uses copy_from_env to read pre-exported verification data from the container.
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_phone(phone_str):
    """Extract digits from phone number for comparison."""
    if not phone_str:
        return ""
    return re.sub(r'\D', '', str(phone_str))


def normalize_text(text):
    """Normalize text for comparison (lowercase, strip whitespace)."""
    if not text:
        return ""
    return str(text).lower().strip()


def verify_add_patient_guarantor(traj, env_info, task_info):
    """
    Verify that guarantor information was correctly added to patient record.

    Scoring (100 points total):
    - Guarantor name contains Maria and Gusikowski: 25 points
    - Address fields correct (city, state, zip): 20 points
    - Phone number correct: 15 points
    - Relationship indicated: 15 points
    - Patient found: 15 points
    - Data was saved (changed from initial): 10 points

    Pass threshold: 70 points with guarantor_name and data_saved criteria met
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_fname = metadata.get('guarantor_fname', 'Maria')
    expected_lname = metadata.get('guarantor_lname', 'Gusikowski')
    expected_city = metadata.get('guarantor_city', 'Northampton')
    expected_state = metadata.get('guarantor_state', 'MA')
    expected_zip = metadata.get('guarantor_zip', '01060')
    expected_phone = metadata.get('guarantor_phone', '4135550198')
    expected_street = metadata.get('guarantor_street', '661 Nikolaus Well')

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/add_guarantor_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "patient_found": False,
            "guarantor_name": False,
            "guarantor_address": False,
            "guarantor_phone": False,
            "relationship": False,
            "data_saved": False
        }

        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        data_present = result.get('data_present', False)
        data_changed = result.get('data_changed', False)
        guarantor = result.get('guarantor_data', {})

        guardian_name = guarantor.get('name', '')
        guardian_street = guarantor.get('street', '')
        guardian_city = guarantor.get('city', '')
        guardian_state = guarantor.get('state', '')
        guardian_zip = guarantor.get('zip', '')
        guardian_phone = guarantor.get('phone', '')

        logger.info(f"Patient PID: {patient_pid}")
        logger.info(f"Guarantor data: {guarantor}")
        logger.info(f"Data present: {data_present}, Data changed: {data_changed}")

        # CRITERION 1: Patient found (15 points)
        if patient_pid and int(patient_pid) > 0:
            score += 15
            subscores["patient_found"] = True
            feedback_parts.append(f"✓ Patient found (PID={patient_pid})")
        else:
            feedback_parts.append("✗ Patient not found in database")
            return {
                "passed": False,
                "score": 0,
                "feedback": "Patient Pedro Gusikowski not found in database",
                "subscores": subscores
            }

        # CRITERION 2: Guarantor name (25 points)
        name_lower = normalize_text(guardian_name)
        fname_match = expected_fname.lower() in name_lower
        lname_match = expected_lname.lower() in name_lower

        if fname_match and lname_match:
            score += 25
            subscores["guarantor_name"] = True
            feedback_parts.append(f"✓ Guarantor name correct: '{guardian_name}'")
        elif fname_match or lname_match:
            score += 10  # Partial credit
            feedback_parts.append(f"~ Guarantor name partial match: '{guardian_name}'")
        else:
            if guardian_name:
                feedback_parts.append(f"✗ Guarantor name incorrect: '{guardian_name}' (expected Maria Gusikowski)")
            else:
                feedback_parts.append("✗ Guarantor name not entered")

        # CRITERION 3: Address fields (20 points)
        address_score = 0
        address_details = []

        # Check city (5 points)
        if normalize_text(guardian_city) == normalize_text(expected_city):
            address_score += 5
            address_details.append("city ✓")
        elif guardian_city:
            address_details.append(f"city: got '{guardian_city}'")

        # Check state (5 points)
        state_normalized = normalize_text(guardian_state)
        if state_normalized in [normalize_text(expected_state), 'massachusetts']:
            address_score += 5
            address_details.append("state ✓")
        elif guardian_state:
            address_details.append(f"state: got '{guardian_state}'")

        # Check zip (5 points)
        if expected_zip in str(guardian_zip):
            address_score += 5
            address_details.append("zip ✓")
        elif guardian_zip:
            address_details.append(f"zip: got '{guardian_zip}'")

        # Check street (5 points)
        street_lower = normalize_text(guardian_street)
        if 'nikolaus' in street_lower or '661' in str(guardian_street):
            address_score += 5
            address_details.append("street ✓")
        elif guardian_street:
            address_details.append(f"street: got '{guardian_street}'")

        score += address_score
        if address_score >= 15:
            subscores["guarantor_address"] = True
            feedback_parts.append(f"✓ Address mostly correct ({', '.join(address_details)})")
        elif address_score > 0:
            feedback_parts.append(f"~ Address partially correct ({', '.join(address_details)})")
        else:
            feedback_parts.append("✗ Address not entered or incorrect")

        # CRITERION 4: Phone number (15 points)
        phone_digits = normalize_phone(guardian_phone)
        expected_digits = normalize_phone(expected_phone)

        if expected_digits and expected_digits in phone_digits:
            score += 15
            subscores["guarantor_phone"] = True
            feedback_parts.append(f"✓ Phone number correct: {guardian_phone}")
        elif len(phone_digits) >= 10:
            score += 5  # Partial credit for entering a phone number
            feedback_parts.append(f"~ Phone entered but different: {guardian_phone}")
        else:
            feedback_parts.append("✗ Phone number not entered or invalid")

        # CRITERION 5: Relationship indicated (15 points)
        # Check if "parent" or similar appears in the name field or any related field
        all_text = normalize_text(f"{guardian_name} {guarantor.get('relationship', '')}")
        relationship_keywords = ['parent', 'mother', 'father', 'mom', 'dad', 'guardian', 'custodian']

        relationship_found = any(kw in all_text for kw in relationship_keywords)

        if relationship_found:
            score += 15
            subscores["relationship"] = True
            feedback_parts.append("✓ Relationship to patient indicated")
        else:
            # OpenEMR may not have a separate relationship field - give partial credit if name is correct
            if subscores["guarantor_name"]:
                score += 7
                feedback_parts.append("~ Relationship not explicitly stated (name is correct)")
            else:
                feedback_parts.append("✗ Relationship to patient not indicated")

        # CRITERION 6: Data was saved (10 points)
        # Anti-gaming: verify data actually changed from empty/initial state
        if data_changed and data_present:
            score += 10
            subscores["data_saved"] = True
            feedback_parts.append("✓ Data successfully saved to database")
        elif data_present:
            score += 5  # Partial - data exists but may have been there before
            feedback_parts.append("~ Data present but unclear if newly added")
        else:
            feedback_parts.append("✗ No guarantor data saved to database")

        # Determine pass/fail
        # Must have: guarantor name correct AND data saved
        key_criteria = subscores["guarantor_name"] and subscores["data_saved"]
        passed = score >= 70 and key_criteria

        # Alternative pass: high score even without perfect criteria
        if score >= 85 and data_present:
            passed = True

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "patient_pid": patient_pid,
                "guarantor_entered": {
                    "name": guardian_name,
                    "street": guardian_street,
                    "city": guardian_city,
                    "state": guardian_state,
                    "zip": guardian_zip,
                    "phone": guardian_phone
                },
                "expected": {
                    "name": f"{expected_fname} {expected_lname}",
                    "city": expected_city,
                    "state": expected_state,
                    "zip": expected_zip,
                    "phone": expected_phone
                }
            }
        }

    except FileNotFoundError:
        logger.error("Result file not found - export may have failed")
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - task export may have failed",
            "subscores": {
                "patient_found": False,
                "guarantor_name": False,
                "guarantor_address": False,
                "guarantor_phone": False,
                "relationship": False,
                "data_saved": False
            }
        }
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse result JSON: {e}",
            "subscores": {
                "patient_found": False,
                "guarantor_name": False,
                "guarantor_address": False,
                "guarantor_phone": False,
                "relationship": False,
                "data_saved": False
            }
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "subscores": {
                "patient_found": False,
                "guarantor_name": False,
                "guarantor_address": False,
                "guarantor_phone": False,
                "relationship": False,
                "data_saved": False
            }
        }


if __name__ == '__main__':
    # For testing - this would normally be called by the framework
    print("Verifier for add_patient_guarantor task")
    print("Run through the task verification framework")