#!/usr/bin/env python3
"""
Verifier for hr_performance_calibration task.

Checks that the agent:
  1. Created a 'Performance Review Calibration' recurring event
  2. Set it to recur monthly
  3. Added HR leadership: Frank Rivera, Grace Patel (CFO), Henry Kim (VP Ops)
  4. Added a description/agenda
  5. Deleted 'Annual Performance Review - Frank Rivera'

Scoring (100 pts total, pass threshold = 70):
  - 'Performance Review Calibration' event exists:    15 pts
  - Event has monthly recurrence:                     25 pts
  - All 3 required attendees present:                 30 pts  (10 pts each)
  - Description/agenda non-empty (>= 20 chars):       10 pts
  - 'Annual Performance Review - Frank Rivera' deleted: 20 pts
"""

import json
import os
import re
import tempfile


def verify_hr_performance_calibration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "Verification error: copy_from_env not available"}

    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env('/tmp/hr_calibration_result.json', tmp_path)
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

    # Criterion 1: Calibration event created (15 pts)
    if result.get('calibration_found'):
        score += 15
        feedback.append("PASS: 'Performance Review Calibration' event found")
    else:
        feedback.append("FAIL: No 'Performance Review Calibration' event found")

    # Criterion 2: Monthly recurrence (25 pts)
    rrule = result.get('rrule', '')
    rrule_type = result.get('rrule_type', '')
    has_recurrence = result.get('has_recurrence', False)
    is_monthly = (
        has_recurrence and (
            'FREQ=MONTHLY' in rrule.upper() or
            rrule_type == 'monthly'
        )
    )
    if is_monthly:
        score += 25
        feedback.append("PASS: Event set to recur monthly")
    elif has_recurrence:
        score += 10
        feedback.append(f"PARTIAL: Event has recurrence but not monthly (rrule_type={rrule_type!r})")
    else:
        feedback.append("FAIL: Event has no recurrence set")

    # Criterion 3: Key attendees (30 pts — 10 each)
    if result.get('has_frank_rivera'):
        score += 10
        feedback.append("PASS: Frank Rivera (HR) added as attendee")
    else:
        feedback.append("FAIL: Frank Rivera not in attendees")

    if result.get('has_grace_patel'):
        score += 10
        feedback.append("PASS: Grace Patel (CFO) added as attendee")
    else:
        feedback.append("FAIL: Grace Patel (CFO) not in attendees")

    if result.get('has_henry_kim'):
        score += 10
        feedback.append("PASS: Henry Kim (VP Operations) added as attendee")
    else:
        feedback.append("FAIL: Henry Kim (VP Operations) not in attendees")

    # Criterion 4: Description/agenda non-empty (10 pts)
    description = result.get('description', '')
    plain_desc = re.sub(r'<[^>]+>', '', description).strip()
    if len(plain_desc) >= 20:
        score += 10
        feedback.append(f"PASS: Description has {len(plain_desc)} chars of agenda content")
    elif len(plain_desc) > 0:
        score += 5
        feedback.append(f"PARTIAL: Description very short ({len(plain_desc)} chars)")
    else:
        feedback.append("FAIL: No description/agenda written")

    # Criterion 5: Annual review deleted (20 pts)
    if result.get('annual_review_deleted'):
        score += 20
        feedback.append("PASS: 'Annual Performance Review - Frank Rivera' deleted")
    else:
        feedback.append("FAIL: 'Annual Performance Review - Frank Rivera' still exists — must be deleted")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }
