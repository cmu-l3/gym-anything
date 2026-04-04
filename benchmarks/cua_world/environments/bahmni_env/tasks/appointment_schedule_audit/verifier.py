#!/usr/bin/env python3
"""
Verifier for appointment_schedule_audit task.

Scoring (100 points):
- Emily Chen rescheduled to +1 hour (within ±20 min tolerance): 30 pts
- Rosa Martinez rescheduled to +2 hours (within ±20 min tolerance): 30 pts
- Priya Patel appointment unchanged (within ±20 min tolerance): 20 pts
- All three appointments are at different time slots: 20 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_appointment_schedule_audit(traj, env_info, task_info):
    """
    Verify appointment schedule conflict was resolved correctly.

    Three patients (Emily Chen, Rosa Martinez, Priya Patel) had conflicting appointments.
    Emily should be moved +1 hour, Rosa +2 hours, Priya unchanged.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env('/tmp/appointment_schedule_audit_result.json', temp_path)
            with open(temp_path, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_path):
                os.unlink(temp_path)

        score = 0
        feedback_parts = []
        subscores = {}

        # Check that we have data for all three patients
        appointments_found = result.get('appointments_found', 0)
        if appointments_found == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No appointment data found — export script may have failed or appointments module unavailable",
                "subscores": {}
            }

        emily = result.get('emily_chen', {})
        rosa = result.get('rosa_martinez', {})
        priya = result.get('priya_patel', {})

        # Criterion 1: Emily Chen rescheduled to +1 hour (30 pts)
        emily_diff = emily.get('diff_from_original_minutes')
        emily_hour = emily.get('start_hour')

        if emily.get('correctly_rescheduled_plus_1hr'):
            score += 30
            subscores['emily_reschedule'] = 30
            feedback_parts.append(f"Emily Chen correctly rescheduled (+{emily_diff} min)")
        elif emily.get('was_changed') and emily_diff is not None:
            # Changed but not to the right time — partial credit
            score += 10
            subscores['emily_reschedule'] = 10
            feedback_parts.append(f"Emily Chen rescheduled but to wrong time (+{emily_diff} min, expected +60 min)")
        elif emily_hour is None:
            subscores['emily_reschedule'] = 0
            feedback_parts.append("Emily Chen appointment not found in system")
        else:
            subscores['emily_reschedule'] = 0
            feedback_parts.append(f"Emily Chen appointment not rescheduled (still at original time, diff={emily_diff} min)")

        # Criterion 2: Rosa Martinez rescheduled to +2 hours (30 pts)
        rosa_diff = rosa.get('diff_from_original_minutes')
        rosa_hour = rosa.get('start_hour')

        if rosa.get('correctly_rescheduled_plus_2hr'):
            score += 30
            subscores['rosa_reschedule'] = 30
            feedback_parts.append(f"Rosa Martinez correctly rescheduled (+{rosa_diff} min)")
        elif rosa.get('was_changed') and rosa_diff is not None:
            score += 10
            subscores['rosa_reschedule'] = 10
            feedback_parts.append(f"Rosa Martinez rescheduled but to wrong time (+{rosa_diff} min, expected +120 min)")
        elif rosa_hour is None:
            subscores['rosa_reschedule'] = 0
            feedback_parts.append("Rosa Martinez appointment not found in system")
        else:
            subscores['rosa_reschedule'] = 0
            feedback_parts.append(f"Rosa Martinez appointment not rescheduled (diff={rosa_diff} min)")

        # Criterion 3: Priya Patel unchanged (20 pts)
        priya_diff = priya.get('diff_from_original_minutes')
        priya_hour = priya.get('start_hour')

        if priya.get('appointment_unchanged'):
            score += 20
            subscores['priya_unchanged'] = 20
            feedback_parts.append("Priya Patel appointment kept at original time (correct)")
        elif priya_hour is None:
            subscores['priya_unchanged'] = 0
            feedback_parts.append("Priya Patel appointment not found in system")
        else:
            subscores['priya_unchanged'] = 0
            feedback_parts.append(f"Priya Patel appointment was incorrectly changed (diff={priya_diff} min from original)")

        # Criterion 4: All three at different times (20 pts)
        if result.get('all_different_times') and appointments_found >= 3:
            score += 20
            subscores['all_different_times'] = 20
            feedback_parts.append("All three appointments at different time slots")
        elif appointments_found < 3:
            subscores['all_different_times'] = 0
            feedback_parts.append(f"Only {appointments_found}/3 appointments found in system")
        else:
            subscores['all_different_times'] = 0
            feedback_parts.append("Two or more appointments still share the same time slot (conflict not fully resolved)")

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
