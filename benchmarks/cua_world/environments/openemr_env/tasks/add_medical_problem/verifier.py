#!/usr/bin/env python3
"""
Verifier for Add Medical Problem task in OpenEMR

Task: Add "Osteoarthritis" to patient Jayson Fadel's problem list
with onset date 2024-01-15.

Verification Strategy:
1. Check problem exists for correct patient (pid=3)
2. Verify it's a NEW record (not pre-existing)
3. Verify diagnosis title contains "osteoarthritis"
4. Verify onset date matches 2024-01-15
5. Verify problem is marked as active

Uses copy_from_env to read pre-exported verification data.
"""

import sys
import os
import json
import logging
import tempfile
import re
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_add_medical_problem(traj, env_info, task_info):
    """
    Verify that osteoarthritis was correctly added to the patient's problem list.

    Scoring (100 points total):
    - Problem record exists for correct patient: 30 points
    - Problem was newly created (not pre-existing): 20 points
    - Diagnosis title contains "osteoarthritis": 25 points
    - Onset date matches 2024-01-15: 15 points
    - Problem is marked as active: 10 points

    Passing threshold: 65 points with problem_exists criterion met
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 3)
    expected_title = metadata.get('expected_problem_title', 'Osteoarthritis').lower()
    expected_onset = metadata.get('expected_onset_date', '2024-01-15')
    expected_type = metadata.get('expected_problem_type', 'medical_problem')

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/medical_problem_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to read result file: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to read verification data: {e}"
            }
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "problem_exists": False,
            "newly_created": False,
            "correct_diagnosis": False,
            "correct_date": False,
            "is_active": False
        }

        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        initial_count = result.get('initial_problem_count', 0)
        current_count = result.get('current_problem_count', 0)
        oa_found = result.get('osteoarthritis_found', False)
        is_new_record = result.get('is_new_record', False)
        preexisting_oa = result.get('preexisting_oa', False)
        problem = result.get('problem', {})
        validation = result.get('validation', {})

        logger.info(f"Result: pid={patient_pid}, initial={initial_count}, current={current_count}")
        logger.info(f"OA found={oa_found}, is_new={is_new_record}, preexisting={preexisting_oa}")
        logger.info(f"Problem data: {problem}")

        # ANTI-GAMING CHECK: Verify we're checking the correct patient
        if patient_pid != expected_pid:
            feedback_parts.append(f"CRITICAL: Wrong patient! Expected pid={expected_pid}, got {patient_pid}")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # ANTI-GAMING CHECK: If osteoarthritis existed before task, fail
        if preexisting_oa:
            feedback_parts.append("GAMING DETECTED: Osteoarthritis existed before task started")
            feedback_parts.append("Agent may have done nothing or used pre-existing data")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # CRITERION 1: Problem record exists for correct patient (30 points)
        if oa_found:
            score += 30
            subscores["problem_exists"] = True
            feedback_parts.append(f"Osteoarthritis found in problem list for pid={expected_pid}")
        else:
            feedback_parts.append(f"Osteoarthritis NOT found in problem list for pid={expected_pid}")
            
            # Check if any new problem was added
            any_new = result.get('any_new_problem_added', False)
            if any_new:
                feedback_parts.append(f"Note: {current_count - initial_count} new problem(s) added, but not osteoarthritis")
            else:
                feedback_parts.append("No new problems were added to the database")
            
            # Early return - can't verify other criteria without the record
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # CRITERION 2: Problem was newly created (20 points)
        if is_new_record:
            score += 20
            subscores["newly_created"] = True
            feedback_parts.append("Problem was newly created during task")
        elif current_count > initial_count:
            # Partial credit if count increased but ID check failed
            score += 10
            feedback_parts.append("Problem count increased but ID verification uncertain")
        else:
            feedback_parts.append("WARNING: Problem may have been pre-existing")

        # CRITERION 3: Diagnosis title contains "osteoarthritis" (25 points)
        problem_title = problem.get('title', '').lower().strip()
        if expected_title in problem_title:
            score += 25
            subscores["correct_diagnosis"] = True
            feedback_parts.append(f"Diagnosis title correct: '{problem.get('title', '')}'")
        elif 'arthritis' in problem_title:
            # Partial credit for close match
            score += 15
            feedback_parts.append(f"Partial match: '{problem.get('title', '')}' (expected 'osteoarthritis')")
        else:
            feedback_parts.append(f"Diagnosis title incorrect: '{problem.get('title', '')}' (expected 'osteoarthritis')")

        # CRITERION 4: Onset date matches expected (15 points)
        onset_date = problem.get('onset_date', '')
        date_matches = validation.get('date_matches_expected', False)
        
        if date_matches or onset_date == expected_onset:
            score += 15
            subscores["correct_date"] = True
            feedback_parts.append(f"Onset date correct: {expected_onset}")
        elif onset_date:
            # Check if date is in reasonable format but wrong value
            feedback_parts.append(f"Onset date incorrect: got '{onset_date}', expected '{expected_onset}'")
        else:
            feedback_parts.append("Onset date not set")

        # CRITERION 5: Problem is marked as active (10 points)
        is_active = validation.get('is_active', False)
        end_date = problem.get('end_date', '')
        activity = problem.get('activity', '')
        
        # Active means: no end date AND activity flag is 1 or empty
        if is_active or (not end_date or end_date in ['', 'NULL', '0000-00-00', None]):
            if activity in ['1', '', None, '1']:
                score += 10
                subscores["is_active"] = True
                feedback_parts.append("Problem marked as active")
            else:
                score += 5
                feedback_parts.append(f"Problem activity flag uncertain: '{activity}'")
        else:
            feedback_parts.append(f"Problem may not be active (end_date: {end_date})")

        # Determine pass/fail
        # Must have: problem exists (30) + newly created (20) + correct diagnosis (25) = minimum 75 for confident pass
        # Passing threshold: 65 points with problem_exists met
        key_criteria_met = subscores["problem_exists"] and (subscores["newly_created"] or current_count > initial_count)
        passed = score >= 65 and key_criteria_met

        # Add summary
        feedback_parts.append(f"Total score: {score}/100")

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "patient_pid": patient_pid,
                "problem_title": problem.get('title', ''),
                "onset_date": onset_date,
                "initial_count": initial_count,
                "final_count": current_count
            }
        }

    except json.JSONDecodeError as e:
        logger.error(f"JSON parse error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse verification data: {e}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification failed with error: {e}"
        }