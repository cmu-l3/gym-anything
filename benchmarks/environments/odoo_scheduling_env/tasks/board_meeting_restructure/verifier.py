#!/usr/bin/env python3
"""
Verifier for board_meeting_restructure task.

Checks that the agent:
  1. Postponed the QBR by at least 5 days (target: exactly 7 days = 1 week)
  2. Added Karen Lee (Legal Counsel) as a QBR attendee
  3. Set an advance email reminder on the QBR
  4. Deleted the 'Budget Committee Meeting'

Scoring (100 pts total, pass threshold = 70):
  - QBR date moved >= 5 days from original:         25 pts
  - Karen Lee added as QBR attendee:                25 pts
  - QBR has >= 1 alarm/reminder:                    20 pts
  - 'Budget Committee Meeting' deleted:             30 pts
"""

import json
import os
import tempfile
from datetime import datetime


def verify_board_meeting_restructure(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "Verification error: copy_from_env not available"}

    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env('/tmp/board_restructure_result.json', tmp_path)
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

    if not result.get('qbr_found'):
        return {"passed": False, "score": 0,
                "feedback": "FAIL: 'Quarterly Business Review' event not found — was it accidentally deleted?"}

    score = 0
    feedback = []

    # Criterion 1: QBR date moved by >= 5 days (25 pts)
    original_start_str = result.get('qbr_original_start', '')
    current_start_str = result.get('qbr_start', '')
    date_moved = False
    days_diff = 0

    if original_start_str and current_start_str:
        try:
            # Odoo XML-RPC returns dates as strings like '2026-03-14 09:00:00'
            # Handle both with and without timezone info
            def parse_dt(s):
                s = str(s).split('+')[0].strip()  # strip tz offset if any
                for fmt in ('%Y-%m-%d %H:%M:%S', '%Y-%m-%dT%H:%M:%S', '%Y-%m-%d'):
                    try:
                        return datetime.strptime(s, fmt)
                    except ValueError:
                        continue
                return None

            original_dt = parse_dt(original_start_str)
            current_dt = parse_dt(current_start_str)

            if original_dt and current_dt:
                days_diff = (current_dt - original_dt).days
                date_moved = days_diff >= 5
        except Exception:
            pass

    if date_moved:
        score += 25
        feedback.append(f"PASS: QBR moved {days_diff} days later (>= 5 days required)")
    elif days_diff > 0:
        score += 10
        feedback.append(f"PARTIAL: QBR moved only {days_diff} day(s) — need >= 5 days (1 week)")
    elif original_start_str and current_start_str:
        feedback.append(f"FAIL: QBR date unchanged (still {current_start_str})")
    else:
        feedback.append("FAIL: Could not compare QBR dates (baseline not recorded)")

    # Criterion 2: Karen Lee added as attendee (25 pts)
    if result.get('karen_lee_attendee'):
        score += 25
        feedback.append("PASS: Karen Lee (Legal Counsel) added to QBR attendees")
    else:
        attendees = result.get('attendee_names', [])
        feedback.append(f"FAIL: Karen Lee not in QBR attendees (current: {attendees})")

    # Criterion 3: QBR has alarm/reminder (20 pts)
    alarm_count = result.get('alarm_count', 0)
    if alarm_count >= 1:
        score += 20
        feedback.append(f"PASS: {alarm_count} reminder(s) set on QBR")
    else:
        feedback.append("FAIL: No reminder/alarm configured on QBR")

    # Criterion 4: Budget Committee Meeting deleted (30 pts)
    if result.get('budget_meeting_deleted'):
        score += 30
        feedback.append("PASS: 'Budget Committee Meeting' deleted")
    else:
        feedback.append("FAIL: 'Budget Committee Meeting' still exists — must be cancelled")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }
