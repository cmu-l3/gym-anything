#!/usr/bin/env python3
"""
Verifier for weekly_ops_review_setup task.

Checks that the agent created a recurring weekly 'Operations Weekly Review' meeting
with at least 3 Northbridge attendees and an email reminder.

Scoring (100 pts total, pass threshold = 70):
  - Event named 'Operations Weekly Review' exists:       20 pts
  - Event has weekly recurrence set:                     25 pts
  - Event has >= 3 Northbridge attendees:                30 pts
  - Event has >= 1 reminder/alarm:                       25 pts
"""

import json
import os
import tempfile


def verify_weekly_ops_review_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "Verification error: copy_from_env not available"}

    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env('/tmp/weekly_ops_review_result.json', tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0,
                "feedback": f"Could not read result file: {e}"}
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    score = 0
    feedback = []

    # Criterion 1: Event exists (20 pts)
    if result.get('event_found'):
        score += 20
        feedback.append("PASS: 'Operations Weekly Review' event found")
    else:
        feedback.append("FAIL: No 'Operations Weekly Review' event found in calendar")

    # Criterion 2: Weekly recurrence set (25 pts)
    rrule = result.get('rrule', '')
    rrule_type = result.get('rrule_type', '')
    has_recurrence = result.get('has_recurrence', False)
    is_weekly = (
        has_recurrence and (
            'FREQ=WEEKLY' in rrule.upper() or
            rrule_type == 'weekly'
        )
    )
    if is_weekly:
        score += 25
        feedback.append("PASS: Event has weekly recurrence configured")
    elif has_recurrence:
        # Partial: has some recurrence but not weekly — still award partial credit
        score += 10
        feedback.append(f"PARTIAL: Event has recurrence but not weekly (rrule_type={rrule_type!r})")
    else:
        feedback.append("FAIL: Event has no recurrence set")

    # Criterion 3: >= 3 Northbridge attendees (30 pts)
    nb_count = result.get('northbridge_attendee_count', 0)
    if nb_count >= 3:
        score += 30
        feedback.append(f"PASS: Event has {nb_count} Northbridge attendees (>= 3 required)")
    elif nb_count >= 1:
        score += 10
        feedback.append(f"PARTIAL: Event has only {nb_count} Northbridge attendee(s) (need >= 3)")
    else:
        feedback.append("FAIL: No Northbridge attendees added to the event")

    # Criterion 4: At least 1 alarm/reminder (25 pts)
    alarm_count = result.get('alarm_count', 0)
    if alarm_count >= 1:
        score += 25
        feedback.append(f"PASS: Event has {alarm_count} reminder(s) configured")
    else:
        feedback.append("FAIL: No reminders/alarms set on the event")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }
