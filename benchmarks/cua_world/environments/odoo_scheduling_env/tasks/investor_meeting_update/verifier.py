#!/usr/bin/env python3
"""
Verifier for investor_meeting_update task.

Checks that the agent updated the 'Investor Update Preparation' event correctly:
  - Added Karen Lee (Legal Counsel) as an attendee
  - Set location to include 'Board Room'
  - Added a substantive agenda/description
  - Configured an email reminder

Scoring (100 pts total, pass threshold = 70):
  - Karen Lee added as attendee:             30 pts
  - Location contains 'board' (any case):    20 pts
  - Description is non-empty (>= 20 chars):  25 pts
  - At least 1 alarm/reminder set:           25 pts
"""

import json
import os
import tempfile


def verify_investor_meeting_update(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "Verification error: copy_from_env not available"}

    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env('/tmp/investor_meeting_result.json', tmp_path)
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

    if not result.get('event_found'):
        return {"passed": False, "score": 0,
                "feedback": "FAIL: 'Investor Update Preparation' event not found in calendar"}

    score = 0
    feedback = []

    # Criterion 1: Karen Lee (Legal Counsel) added as attendee (30 pts)
    if result.get('karen_lee_attendee'):
        score += 30
        feedback.append("PASS: Karen Lee (Legal Counsel) added as attendee")
    else:
        attendees = result.get('attendee_names', [])
        feedback.append(f"FAIL: Karen Lee not found in attendees (current: {attendees})")

    # Criterion 2: Location contains 'board' (20 pts)
    location = result.get('location', '')
    if 'board' in location.lower():
        score += 20
        feedback.append(f"PASS: Location set to '{location}' (contains 'board')")
    else:
        feedback.append(f"FAIL: Location is '{location}' — expected Board Room")

    # Criterion 3: Description/agenda is non-empty (>= 20 chars) (25 pts)
    description = result.get('description', '')
    # Strip HTML tags if present (Odoo stores description as HTML)
    import re
    plain_desc = re.sub(r'<[^>]+>', '', description).strip()
    if len(plain_desc) >= 20:
        score += 25
        feedback.append(f"PASS: Description has {len(plain_desc)} chars of agenda content")
    elif len(plain_desc) > 0:
        score += 10
        feedback.append(f"PARTIAL: Description is very short ({len(plain_desc)} chars) — needs more content")
    else:
        feedback.append("FAIL: Description/agenda is empty")

    # Criterion 4: At least 1 alarm/reminder (25 pts)
    alarm_count = result.get('alarm_count', 0)
    if alarm_count >= 1:
        score += 25
        feedback.append(f"PASS: {alarm_count} reminder(s) configured")
    else:
        feedback.append("FAIL: No reminders/alarms set on the event")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }
