#!/usr/bin/env python3
"""
Verifier for q2_restructuring_transition task.

Checks that the agent executed a full calendar transition for a departing VP:
  1. Created Rachel Torres contact with correct details
  2. Modified ALL occurrences of recurring 'Operations Daily Sync':
     replaced Henry Kim with Rachel Torres, changed location
  3. Rescheduled 'Quarterly Business Review' +7 days, swapped attendees,
     updated description
  4. Created recurring 'Operations Transition Check-in' with Mon+Thu pattern,
     correct attendees, description, and reminder

Scoring (100 pts total, pass threshold = 70):
  - Rachel Torres contact exists with correct email:        8 pts
  - Ops Daily Sync: Henry Kim removed:                     10 pts
  - Ops Daily Sync: Rachel Torres added:                   10 pts
  - Ops Daily Sync: Location changed to Virtual (Zoom):     5 pts
  - QBR: Rescheduled ~7 days later (5-9 day tolerance):   15 pts
  - QBR: Henry Kim removed:                                 5 pts
  - QBR: Rachel Torres added:                               5 pts
  - QBR: Description updated:                               7 pts
  - Transition Check-in: Event exists:                       5 pts
  - Transition Check-in: Is recurring:                       8 pts
  - Transition Check-in: Mon AND Thu day flags:              7 pts
  - Transition Check-in: Start time ~9:00 AM:                3 pts
  - Transition Check-in: >= 2 attendees:                     4 pts
  - Transition Check-in: Reminder configured:                5 pts
  - Transition Check-in: Description >= 15 chars:            3 pts
"""

import json
import os
import re
import tempfile
from datetime import datetime, timedelta


def verify_q2_restructuring_transition(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "Verification error: copy_from_env not available"}

    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env('/tmp/task_result.json', tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found - export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0,
                "feedback": f"Could not read result file: {e}"}
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    if result.get('error'):
        return {"passed": False, "score": 0,
                "feedback": f"Export error: {result['error']}"}

    score = 0
    feedback = []

    # ==================================================================
    # Criterion 1: Rachel Torres contact (8 pts)
    # ==================================================================
    rachel = result.get('rachel_contact', {})
    if rachel.get('exists'):
        email = (rachel.get('email') or '').lower().strip()
        if 'rachel' in email and 'torres' in email and 'northbridge' in email:
            score += 8
            feedback.append("PASS: Rachel Torres contact with correct email")
        else:
            score += 3
            feedback.append(f"PARTIAL: Rachel Torres exists but email mismatch ({email})")
    else:
        feedback.append("FAIL: Rachel Torres contact not found")

    # ==================================================================
    # Criterion 2: Operations Daily Sync modifications (25 pts)
    # ==================================================================
    sync = result.get('ops_daily_sync', {})
    if sync.get('exists'):
        # Henry Kim removed (10 pts)
        if not sync.get('has_henry_kim'):
            score += 10
            feedback.append("PASS: Henry Kim removed from Ops Daily Sync")
        else:
            feedback.append("FAIL: Henry Kim still in Ops Daily Sync attendees")

        # Rachel Torres added (10 pts)
        if sync.get('has_rachel_torres'):
            score += 10
            feedback.append("PASS: Rachel Torres added to Ops Daily Sync")
        else:
            feedback.append("FAIL: Rachel Torres not in Ops Daily Sync attendees")

        # Location changed (5 pts)
        location = (sync.get('location') or '').lower()
        if 'virtual' in location or 'zoom' in location:
            score += 5
            feedback.append("PASS: Ops Daily Sync location updated to Virtual/Zoom")
        else:
            feedback.append(f"FAIL: Ops Daily Sync location not updated ({sync.get('location')})")
    else:
        feedback.append("FAIL: Operations Daily Sync event not found")

    # ==================================================================
    # Criterion 3: QBR rescheduled + modified (32 pts)
    # ==================================================================
    qbr = result.get('qbr', {})
    original_date_str = result.get('qbr_original_date', '')

    if qbr.get('exists') and original_date_str:
        # Parse dates - handle both 'YYYY-MM-DD HH:MM:SS' and 'YYYY-MM-DD' formats
        try:
            if ' ' in original_date_str:
                original_dt = datetime.strptime(original_date_str, '%Y-%m-%d %H:%M:%S')
            else:
                original_dt = datetime.strptime(original_date_str, '%Y-%m-%d')

            new_start_str = qbr.get('start', '')
            if ' ' in new_start_str:
                new_dt = datetime.strptime(new_start_str, '%Y-%m-%d %H:%M:%S')
            else:
                new_dt = datetime.strptime(new_start_str, '%Y-%m-%d')

            day_diff = (new_dt.date() - original_dt.date()).days

            # Rescheduled ~7 days later (15 pts, tolerance 5-9 days)
            if 5 <= day_diff <= 9:
                score += 15
                feedback.append(f"PASS: QBR rescheduled {day_diff} days later")
            elif 1 <= day_diff <= 14:
                score += 7
                feedback.append(f"PARTIAL: QBR moved {day_diff} days (expected ~7)")
            else:
                feedback.append(f"FAIL: QBR date diff is {day_diff} days (expected ~7)")
        except ValueError as e:
            feedback.append(f"FAIL: Could not parse QBR dates ({e})")

        # Henry Kim removed (5 pts)
        if not qbr.get('has_henry_kim'):
            score += 5
            feedback.append("PASS: Henry Kim removed from QBR")
        else:
            feedback.append("FAIL: Henry Kim still in QBR attendees")

        # Rachel Torres added (5 pts)
        if qbr.get('has_rachel_torres'):
            score += 5
            feedback.append("PASS: Rachel Torres added to QBR")
        else:
            feedback.append("FAIL: Rachel Torres not in QBR attendees")

        # Description updated (7 pts)
        desc = qbr.get('description', '') or ''
        plain_desc = re.sub(r'<[^>]+>', '', desc).lower().strip()
        if 'restructuring' in plain_desc or 'reporting' in plain_desc or 'kpi' in plain_desc:
            score += 7
            feedback.append("PASS: QBR description updated with restructuring agenda")
        elif len(plain_desc) > 80:
            score += 3
            feedback.append("PARTIAL: QBR description changed but missing key terms")
        else:
            feedback.append("FAIL: QBR description not updated")
    elif not qbr.get('exists'):
        feedback.append("FAIL: Quarterly Business Review event not found (may have been deleted)")
    else:
        feedback.append("FAIL: QBR original date not available for comparison")

    # ==================================================================
    # Criterion 4: Operations Transition Check-in (35 pts)
    # ==================================================================
    checkin = result.get('transition_checkin', {})
    if checkin.get('exists'):
        score += 5
        feedback.append("PASS: Operations Transition Check-in event found")

        # Is recurring (8 pts)
        if checkin.get('recurrency'):
            score += 8
            feedback.append("PASS: Transition Check-in is recurring")
        else:
            feedback.append("FAIL: Transition Check-in is not recurring")

        # Mon AND Thu flags (7 pts)
        if checkin.get('mon') and checkin.get('thu'):
            score += 7
            feedback.append("PASS: Transition Check-in repeats on Mon and Thu")
        elif checkin.get('mon') or checkin.get('thu'):
            score += 3
            feedback.append("PARTIAL: Transition Check-in has only one of Mon/Thu")
        else:
            # Check rrule string as fallback
            rrule = checkin.get('rrule_type', '')
            if rrule == 'weekly':
                score += 2
                feedback.append("PARTIAL: Weekly recurrence but day flags not confirmed")
            else:
                feedback.append("FAIL: Transition Check-in day pattern incorrect")

        # Start time ~9:00 AM (3 pts)
        start_str = checkin.get('start', '')
        if start_str:
            try:
                start_dt = datetime.strptime(start_str, '%Y-%m-%d %H:%M:%S')
                if 8 <= start_dt.hour <= 9:
                    score += 3
                    feedback.append("PASS: Transition Check-in starts around 9:00 AM")
                else:
                    feedback.append(f"FAIL: Transition Check-in starts at {start_dt.hour}:00")
            except ValueError:
                feedback.append("FAIL: Could not parse Transition Check-in start time")

        # >= 2 attendees (4 pts)
        attendee_count = len(checkin.get('attendee_names', []))
        if attendee_count >= 2:
            score += 4
            feedback.append(f"PASS: Transition Check-in has {attendee_count} attendees")
        else:
            feedback.append(f"FAIL: Transition Check-in has only {attendee_count} attendees")

        # Reminder configured (5 pts)
        if checkin.get('alarm_count', 0) >= 1:
            score += 5
            feedback.append("PASS: Transition Check-in has reminder")
        else:
            feedback.append("FAIL: No reminder on Transition Check-in")

        # Description >= 15 chars (3 pts)
        desc = checkin.get('description', '') or ''
        plain_desc = re.sub(r'<[^>]+>', '', desc).strip()
        if len(plain_desc) >= 15:
            score += 3
            feedback.append("PASS: Transition Check-in has description")
        else:
            feedback.append("FAIL: Transition Check-in description too short or missing")
    else:
        feedback.append("FAIL: Operations Transition Check-in event not found")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }
