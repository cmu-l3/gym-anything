#!/usr/bin/env python3
"""
Verifier for Update Patient Demographics task in OpenEMR

Robust verification with multi-criteria scoring:
1. Correct patient was modified (pid=3, Jayson Fadel)
2. Street address contains expected value
3. City was updated correctly
4. Postal code was updated correctly
5. Home phone was updated correctly
6. Cell phone was updated correctly
7. State remained unchanged (MA)
8. Anti-gaming: Data actually changed from initial state

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


def digits_only(phone_str):
    """Extract only digits from a phone number string."""
    if not phone_str:
        return ""
    return ''.join(c for c in str(phone_str) if c.isdigit())


def verify_update_patient_demographics(traj, env_info, task_info):
    """
    Verify that patient demographics were correctly updated.

    Scoring (100 points total):
    - Correct patient identified (pid=3): 15 points
    - Street address updated correctly: 20 points
    - City updated correctly: 15 points
    - Postal code updated correctly: 15 points
    - Home phone updated correctly: 15 points
    - Cell phone updated correctly: 15 points
    - State preserved (MA): 5 points

    Anti-gaming:
    - Data must have actually changed from initial state
    - Penalty applied if no changes detected

    Passing threshold: 70 points with correct patient mandatory
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 3)
    expected_fname = metadata.get('patient_fname', 'Jayson')
    expected_lname = metadata.get('patient_lname', 'Fadel')
    expected_street = metadata.get('expected_street', '742 Evergreen Terrace')
    expected_unit = metadata.get('expected_unit', 'Unit 3A')
    expected_city = metadata.get('expected_city', 'Springfield')
    expected_state = metadata.get('expected_state', 'MA')
    expected_postal = metadata.get('expected_postal', '01103')
    expected_phone_home = metadata.get('expected_phone_home', '413-555-0842')
    expected_phone_cell = metadata.get('expected_phone_cell', '413-555-9173')

    # Extract expected digits for flexible phone matching
    expected_home_digits = digits_only(expected_phone_home)
    expected_cell_digits = digits_only(expected_phone_cell)

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/update_demographics_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "correct_patient": False,
            "street_updated": False,
            "city_updated": False,
            "postal_updated": False,
            "phone_home_updated": False,
            "phone_cell_updated": False,
            "state_preserved": False,
            "data_changed": False
        }

        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        patient_identity = result.get('patient_identity', {})
        current_values = result.get('current_values', {})
        initial_values = result.get('initial_values', {})
        changes_detected = result.get('changes_detected', {})

        logger.info(f"Verifying demographics for patient pid={patient_pid}")
        logger.info(f"Current values: {current_values}")
        logger.info(f"Initial values: {initial_values}")
        logger.info(f"Changes detected: {changes_detected}")

        # =================================================================
        # CRITERION 1: Correct patient (15 points)
        # This is mandatory - must modify the right patient
        # =================================================================
        actual_fname = patient_identity.get('fname', '')
        actual_lname = patient_identity.get('lname', '')

        if patient_pid == expected_pid:
            if actual_fname.lower() == expected_fname.lower() and actual_lname.lower() == expected_lname.lower():
                score += 15
                subscores["correct_patient"] = True
                feedback_parts.append(f"Correct patient: {actual_fname} {actual_lname} (pid={patient_pid})")
            else:
                feedback_parts.append(f"Patient ID matches but name mismatch: expected {expected_fname} {expected_lname}, got {actual_fname} {actual_lname}")
                score += 10  # Partial credit for correct PID
        else:
            feedback_parts.append(f"CRITICAL: Wrong patient! Expected pid={expected_pid}, got {patient_pid}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Modified wrong patient (expected pid={expected_pid})",
                "subscores": subscores
            }

        # =================================================================
        # CRITERION 2: Street address updated (20 points)
        # Must contain "742 Evergreen Terrace"
        # =================================================================
        current_street = current_values.get('street', '')
        street_lower = current_street.lower()

        if expected_street.lower() in street_lower:
            score += 20
            subscores["street_updated"] = True
            feedback_parts.append(f"Street address correct: '{current_street}'")
        elif '742' in current_street and 'evergreen' in street_lower:
            # Partial match
            score += 15
            subscores["street_updated"] = True
            feedback_parts.append(f"Street address partially correct: '{current_street}'")
        else:
            feedback_parts.append(f"Street address NOT updated correctly: '{current_street}' (expected contains '{expected_street}')")

        # =================================================================
        # CRITERION 3: City updated (15 points)
        # =================================================================
        current_city = current_values.get('city', '')

        if current_city.lower() == expected_city.lower():
            score += 15
            subscores["city_updated"] = True
            feedback_parts.append(f"City correct: '{current_city}'")
        else:
            feedback_parts.append(f"City NOT updated correctly: '{current_city}' (expected '{expected_city}')")

        # =================================================================
        # CRITERION 4: Postal code updated (15 points)
        # =================================================================
        current_postal = current_values.get('postal_code', '')

        if current_postal == expected_postal:
            score += 15
            subscores["postal_updated"] = True
            feedback_parts.append(f"Postal code correct: '{current_postal}'")
        elif expected_postal in str(current_postal):
            score += 10
            subscores["postal_updated"] = True
            feedback_parts.append(f"Postal code partially correct: '{current_postal}'")
        else:
            feedback_parts.append(f"Postal code NOT updated correctly: '{current_postal}' (expected '{expected_postal}')")

        # =================================================================
        # CRITERION 5: Home phone updated (15 points)
        # Flexible matching - check for expected digits
        # =================================================================
        current_phone_home = current_values.get('phone_home', '')
        current_home_digits = digits_only(current_phone_home)

        if expected_home_digits in current_home_digits or current_home_digits == expected_home_digits:
            score += 15
            subscores["phone_home_updated"] = True
            feedback_parts.append(f"Home phone correct: '{current_phone_home}'")
        elif len(current_home_digits) >= 10 and current_home_digits[-4:] == expected_home_digits[-4:]:
            # Last 4 digits match - partial credit
            score += 8
            feedback_parts.append(f"Home phone partially correct: '{current_phone_home}'")
        else:
            feedback_parts.append(f"Home phone NOT updated correctly: '{current_phone_home}' (expected '{expected_phone_home}')")

        # =================================================================
        # CRITERION 6: Cell phone updated (15 points)
        # =================================================================
        current_phone_cell = current_values.get('phone_cell', '')
        current_cell_digits = digits_only(current_phone_cell)

        if expected_cell_digits in current_cell_digits or current_cell_digits == expected_cell_digits:
            score += 15
            subscores["phone_cell_updated"] = True
            feedback_parts.append(f"Cell phone correct: '{current_phone_cell}'")
        elif len(current_cell_digits) >= 10 and current_cell_digits[-4:] == expected_cell_digits[-4:]:
            # Last 4 digits match - partial credit
            score += 8
            feedback_parts.append(f"Cell phone partially correct: '{current_phone_cell}'")
        else:
            feedback_parts.append(f"Cell phone NOT updated correctly: '{current_phone_cell}' (expected '{expected_phone_cell}')")

        # =================================================================
        # CRITERION 7: State preserved (5 points)
        # State should remain MA (not accidentally cleared)
        # =================================================================
        current_state = current_values.get('state', '')

        if current_state.upper() == expected_state.upper():
            score += 5
            subscores["state_preserved"] = True
            feedback_parts.append(f"State preserved: '{current_state}'")
        else:
            feedback_parts.append(f"WARNING: State changed or cleared: '{current_state}' (expected '{expected_state}')")

        # =================================================================
        # ANTI-GAMING: Check that data actually changed
        # =================================================================
        any_change = changes_detected.get('any_change', False)

        if any_change:
            subscores["data_changed"] = True
            feedback_parts.append("Data was modified during task")
        else:
            # Check if current matches initial (agent did nothing)
            initial_street = initial_values.get('street', '')
            initial_city = initial_values.get('city', '')

            if current_street == initial_street and current_city == initial_city:
                # Penalize for no changes made
                penalty = min(30, score)
                score -= penalty
                feedback_parts.append(f"ANTI-GAMING: No changes detected from initial state (penalty: -{penalty})")
            else:
                subscores["data_changed"] = True

        # =================================================================
        # Final scoring
        # =================================================================
        # Passing requires correct patient + at least 55 more points
        key_criteria_met = subscores["correct_patient"] and subscores["data_changed"]
        passed = score >= 70 and key_criteria_met

        logger.info(f"Final score: {score}/100, passed: {passed}")
        logger.info(f"Subscores: {subscores}")

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "patient_pid": patient_pid,
                "current_values": current_values,
                "expected_values": {
                    "street": expected_street,
                    "city": expected_city,
                    "state": expected_state,
                    "postal": expected_postal,
                    "phone_home": expected_phone_home,
                    "phone_cell": expected_phone_cell
                }
            }
        }

    except FileNotFoundError as e:
        logger.error(f"Result file not found: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export may have failed",
            "subscores": {
                "correct_patient": False,
                "street_updated": False,
                "city_updated": False,
                "postal_updated": False,
                "phone_home_updated": False,
                "phone_cell_updated": False,
                "state_preserved": False,
                "data_changed": False
            }
        }
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid result JSON: {e}",
            "subscores": {}
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "subscores": {}
        }


if __name__ == "__main__":
    # For local testing
    print("Update Patient Demographics Verifier")
    print("Run via gym-anything framework for actual verification")