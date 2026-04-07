#!/usr/bin/env python3
"""
Verifier for Add Patient task in OpenEMR

Uses copy_from_env to read pre-exported verification data from the container.
The export_result.sh script queries the database and saves results to JSON.
"""

import sys
import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_add_patient(traj, env_info, task_info):
    """
    Verify that the expected patient was added to OpenEMR.

    The expected patient details are read from task_info metadata.
    Defaults: John TestPatient, DOB 1985-03-15, Male

    Checks:
    1. Patient with expected fname and lname exists in database
    2. Patient DOB matches expected value
    3. Patient sex matches expected value
    4. Patient was created during this session (pid > initial count)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task_info metadata (with defaults)
    metadata = task_info.get('metadata', {})
    expected_fname = metadata.get('expected_fname', 'John')
    expected_lname = metadata.get('expected_lname', 'TestPatient')
    expected_dob = metadata.get('expected_dob', '1985-03-15')
    expected_sex = metadata.get('expected_sex', 'Male')

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/add_patient_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        criteria_passed = 0
        total_criteria = 4
        feedback_parts = []

        initial_count = result.get('initial_patient_count', 0)
        current_count = result.get('current_patient_count', 0)
        patient_found = result.get('patient_found', False)
        patient = result.get('patient', {})

        logger.info(f"Result data: initial={initial_count}, current={current_count}, found={patient_found}")
        logger.info(f"Patient data: {patient}")

        # Criterion 1: Check if patient exists with expected name
        if patient_found:
            fname = patient.get('fname', '')
            lname = patient.get('lname', '')

            if fname.lower() == expected_fname.lower() and lname.lower() == expected_lname.lower():
                criteria_passed += 1
                feedback_parts.append(f"Patient '{expected_fname} {expected_lname}' found in database")
            else:
                feedback_parts.append(f"Patient name mismatch: expected '{expected_fname} {expected_lname}', got '{fname} {lname}'")
        else:
            feedback_parts.append(f"Patient '{expected_fname} {expected_lname}' NOT found in database")

            # Check if any new patients were added at all
            if current_count > initial_count:
                new_patients = current_count - initial_count
                feedback_parts.append(f"Note: {new_patients} new patient(s) added, but not with expected name")
            else:
                feedback_parts.append("No new patients were added to the database")

            # Early return since no patient found
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": {
                    "patient_exists": False,
                    "dob_correct": False,
                    "sex_correct": False,
                    "newly_added": False
                }
            }

        # Criterion 2: Check DOB
        dob = patient.get('dob', '')
        if dob == expected_dob:
            criteria_passed += 1
            feedback_parts.append(f"DOB correct: {expected_dob}")
        else:
            feedback_parts.append(f"DOB incorrect: expected {expected_dob}, got {dob}")

        # Criterion 3: Check sex
        sex = patient.get('sex', '')
        if sex.lower() in [expected_sex.lower(), expected_sex[0].lower()]:
            criteria_passed += 1
            feedback_parts.append(f"Sex correct: {expected_sex}")
        else:
            feedback_parts.append(f"Sex incorrect: expected {expected_sex}, got {sex}")

        # Criterion 4: Check if patient was newly added (pid > initial count)
        pid_str = patient.get('pid', '0')
        try:
            pid = int(pid_str) if pid_str else 0
            if pid > initial_count:
                criteria_passed += 1
                feedback_parts.append(f"Patient newly added with pid={pid} (initial count was {initial_count})")
            else:
                feedback_parts.append(f"Patient may have existed before task (pid={pid}, initial_count={initial_count})")
                # Still give partial credit since patient exists with correct details
                criteria_passed += 0.5
        except (ValueError, TypeError):
            feedback_parts.append(f"Could not verify patient ID: {pid_str}")

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75  # Pass if at least 3 out of 4 criteria met

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "patient_exists": patient_found,
                "dob_correct": dob == expected_dob,
                "sex_correct": sex.lower() in [expected_sex.lower(), expected_sex[0].lower()],
                "newly_added": criteria_passed >= 4
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