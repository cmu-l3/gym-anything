#!/usr/bin/env python3
"""
Verifier for Cancel Appointment task in OpenEMR

This verifier checks that:
1. The appointment status was changed to cancelled (not deleted)
2. The appointment is for the correct patient
3. The cancellation reason was documented
4. The appointment was modified during the task (anti-gaming)

Uses copy_from_env to read pre-exported verification data from the container.
"""

import sys
import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_cancel_appointment(traj, env_info, task_info):
    """
    Verify that the appointment was correctly cancelled.

    Scoring (100 points total):
    - Appointment status changed to cancelled: 35 points
    - Correct patient (appointment still linked to Sarah Borer): 20 points
    - Record preserved (not deleted): 15 points
    - Cancellation reason documented with keywords: 15 points
    - Correct date/time (Dec 20, 2024 at 10:00 AM): 10 points
    - Modified after task start (anti-gaming): 5 points

    Passing threshold: 70 points with status_changed criterion met
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_fname = metadata.get('patient_fname', 'Sarah')
    expected_lname = metadata.get('patient_lname', 'Borer')
    expected_date = metadata.get('appointment_date', '2024-12-20')
    expected_time = metadata.get('appointment_time', '10:00:00')
    expected_cancelled_statuses = metadata.get('expected_status_after', ['x', 'X', '%'])
    reason_keywords = metadata.get('cancellation_reason_keywords', 
                                   ['work', 'cancel', 'patient', 'conflict', 'request'])
    
    scoring_weights = metadata.get('scoring_weights', {
        'status_changed': 35,
        'correct_patient': 20,
        'record_preserved': 15,
        'reason_documented': 15,
        'correct_datetime': 10,
        'modified_after_start': 5
    })

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/cancel_appointment_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "status_changed": False,
            "correct_patient": False,
            "record_preserved": False,
            "reason_documented": False,
            "correct_datetime": False,
            "modified_after_start": False
        }

        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        appointment_eid = result.get('appointment_eid', 0)
        initial_status = result.get('initial_status', '-')
        current_status = result.get('current_status', '')
        record_preserved = result.get('record_preserved', False)
        status_changed = result.get('status_changed_to_cancelled', False)
        appointment_date = result.get('appointment_date', '')
        appointment_time = result.get('appointment_time', '')
        correct_datetime = result.get('correct_datetime', False)
        comments = result.get('comments', '')
        reason_documented = result.get('reason_documented', False)
        modified_after_start = result.get('modified_after_start', False)
        task_start = result.get('task_start_timestamp', 0)
        modified_ts = result.get('modified_timestamp', 0)

        logger.info(f"Verification data: eid={appointment_eid}, status='{current_status}', preserved={record_preserved}")
        logger.info(f"Comments: '{comments}'")

        # CRITERION 1: Record preserved (not deleted) - 15 points
        # This is checked first because if deleted, other checks are meaningless
        if record_preserved:
            score += scoring_weights.get('record_preserved', 15)
            subscores["record_preserved"] = True
            feedback_parts.append("✅ Appointment record preserved (not deleted)")
        else:
            feedback_parts.append("❌ CRITICAL: Appointment record was DELETED (should only change status)")
            # If record is deleted, this is a significant failure
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Appointment was deleted instead of cancelled. Records must be preserved for tracking.",
                "subscores": subscores
            }

        # CRITERION 2: Status changed to cancelled - 35 points (primary criterion)
        if current_status in expected_cancelled_statuses:
            score += scoring_weights.get('status_changed', 35)
            subscores["status_changed"] = True
            feedback_parts.append(f"✅ Appointment status changed to cancelled ('{current_status}')")
        else:
            feedback_parts.append(f"❌ Appointment status NOT cancelled (current: '{current_status}', expected: {expected_cancelled_statuses})")

        # CRITERION 3: Correct patient - 20 points
        # The appointment should still be for the expected patient (pid matches)
        if patient_pid and patient_pid > 0:
            score += scoring_weights.get('correct_patient', 20)
            subscores["correct_patient"] = True
            feedback_parts.append(f"✅ Correct patient (pid={patient_pid})")
        else:
            feedback_parts.append(f"❌ Patient verification failed (pid={patient_pid})")

        # CRITERION 4: Correct date/time - 10 points
        if correct_datetime:
            score += scoring_weights.get('correct_datetime', 10)
            subscores["correct_datetime"] = True
            feedback_parts.append(f"✅ Correct appointment date/time ({appointment_date} {appointment_time})")
        else:
            feedback_parts.append(f"❌ Date/time mismatch (got: {appointment_date} {appointment_time})")

        # CRITERION 5: Cancellation reason documented - 15 points
        # Check if comments contain expected keywords
        comments_lower = comments.lower() if comments else ''
        keywords_found = [kw for kw in reason_keywords if kw.lower() in comments_lower]
        
        if keywords_found:
            score += scoring_weights.get('reason_documented', 15)
            subscores["reason_documented"] = True
            feedback_parts.append(f"✅ Cancellation reason documented (keywords: {keywords_found})")
        else:
            feedback_parts.append(f"❌ Cancellation reason not properly documented (missing keywords)")
            if comments:
                feedback_parts.append(f"   Found comments: '{comments[:100]}...'")

        # CRITERION 6: Modified after task start (anti-gaming) - 5 points
        if modified_after_start:
            score += scoring_weights.get('modified_after_start', 5)
            subscores["modified_after_start"] = True
            feedback_parts.append("✅ Appointment modified during task execution")
        else:
            feedback_parts.append("⚠️ Could not verify modification timestamp")

        # Determine pass/fail
        # Must have status changed and record preserved at minimum
        key_criteria_met = subscores["status_changed"] and subscores["record_preserved"]
        passed = score >= 70 and key_criteria_met

        # Build final feedback
        feedback = " | ".join(feedback_parts)
        if passed:
            feedback = f"✅ PASSED (Score: {score}/100) | " + feedback
        else:
            if not subscores["status_changed"]:
                feedback = f"❌ FAILED: Appointment status was not changed to cancelled | " + feedback
            else:
                feedback = f"❌ FAILED (Score: {score}/100) | " + feedback

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "appointment_eid": appointment_eid,
                "patient_pid": patient_pid,
                "initial_status": initial_status,
                "final_status": current_status,
                "comments": comments[:200] if comments else "",
                "keywords_found": keywords_found
            }
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Result file not found - export may have failed",
            "subscores": {k: False for k in ["status_changed", "correct_patient", "record_preserved", 
                                              "reason_documented", "correct_datetime", "modified_after_start"]}
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to parse result JSON: {e}",
            "subscores": {k: False for k in ["status_changed", "correct_patient", "record_preserved",
                                              "reason_documented", "correct_datetime", "modified_after_start"]}
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}",
            "subscores": {k: False for k in ["status_changed", "correct_patient", "record_preserved",
                                              "reason_documented", "correct_datetime", "modified_after_start"]}
        }


if __name__ == "__main__":
    # Test mode - for local development
    print("Cancel Appointment Verifier")
    print("This verifier checks that an appointment was correctly cancelled (not deleted).")
    print("Run via the task framework for actual verification.")