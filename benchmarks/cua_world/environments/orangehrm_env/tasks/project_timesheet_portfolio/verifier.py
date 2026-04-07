#!/usr/bin/env python3
"""
Verifier for project_timesheet_portfolio task.

Context: HopeWell Community Services Operations Manager must configure the
Q2 project portfolio in OrangeHRM (2 clients, 2 projects, 4 activities)
and submit timesheets for 2 employees for week of April 7-11, 2025.

Scoring (100 pts total, pass threshold 50):

Client creation (20 pts):
  - 'Riverside Community Foundation' customer exists:  10 pts
  - 'Metro School District' customer exists:           10 pts

Project creation (20 pts):
  - 'After-School Program Expansion' project exists:   10 pts
  - 'Digital Literacy Initiative' project exists:      10 pts

Activity creation (20 pts):
  - 'Program Planning' activity exists (After-School): 5 pts
  - 'Community Outreach' activity exists (After-School): 5 pts
  - 'Curriculum Development' activity exists (Digital): 5 pts
  - 'Instructor Training' activity exists (Digital):    5 pts

Timesheet submission (40 pts):
  - Michael Thompson has timesheet for April 7-11, 2025:  10 pts
  - Michael Thompson logged >= 8 hours that week:         10 pts
  - Kevin Hernandez has timesheet for April 7-11, 2025:  10 pts
  - Kevin Hernandez logged >= 8 hours that week:         10 pts

Total: 100 pts. Pass threshold: 65.
Do-nothing: score=0 (clients/projects deleted by setup, no timesheets).

Anti-Pattern 4 check:
  All infrastructure (clients+projects+activities) but NO timesheets:
    10+10+10+10+5+5+5+5 = 60 pts < threshold 65 ✓ (must enter at least one timesheet to pass)

Note: Timesheet hours are stored in seconds in ohrm_timesheet_item.duration,
OR as decimal hours — the export script sums duration directly.
We accept >= 8 as the lower bound (roughly 1 working day) since exact
hour counts depend on how agents interpret the spec.
"""

import json
import os
import tempfile


def verify_project_timesheet_portfolio(traj, env_info, task_info):
    result_path = task_info.get("metadata", {}).get(
        "result_file", "/tmp/project_timesheet_portfolio_result.json"
    )

    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        env_info["copy_from_env"](result_path, local_tmp)
        with open(local_tmp, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read result file '{result_path}': {e}",
        }
    finally:
        if os.path.exists(local_tmp):
            os.remove(local_tmp)

    score = 0
    feedback_parts = []

    def check_bool(key, label, pts):
        nonlocal score
        val = data.get(key, False)
        if val is True or val == "true":
            score += pts
            feedback_parts.append(f"PASS {label} (+{pts})")
        else:
            feedback_parts.append(f"FAIL {label} (+0)")

    # -------------------------------------------------------
    # Client checks
    # -------------------------------------------------------
    check_bool("riverside_exists", "Riverside Community Foundation client created", 10)
    check_bool("metro_exists", "Metro School District client created", 10)

    # -------------------------------------------------------
    # Project checks
    # -------------------------------------------------------
    check_bool("afterschool_exists", "After-School Program Expansion project created", 10)
    check_bool("digital_exists", "Digital Literacy Initiative project created", 10)

    # -------------------------------------------------------
    # Activity checks
    # -------------------------------------------------------
    check_bool("activity_planning_exists", "Program Planning activity created", 5)
    check_bool("activity_outreach_exists", "Community Outreach activity created", 5)
    check_bool("activity_curriculum_exists", "Curriculum Development activity created", 5)
    check_bool("activity_training_exists", "Instructor Training activity created", 5)

    # -------------------------------------------------------
    # Timesheet checks
    # -------------------------------------------------------
    michael_ts = int(data.get("michael_timesheet_count", 0) or 0)
    michael_hours_raw = float(data.get("michael_total_hours", 0) or 0)
    kevin_ts = int(data.get("kevin_timesheet_count", 0) or 0)
    kevin_hours_raw = float(data.get("kevin_total_hours", 0) or 0)

    # OrangeHRM stores duration in seconds (3600 = 1 hour) or as integer hours.
    # If values are very large (>3600), they're in seconds; divide by 3600.
    # If values are small (<100), they're already in hours.
    def normalize_hours(raw):
        if raw > 100:
            return raw / 3600.0
        return raw

    michael_hours = normalize_hours(michael_hours_raw)
    kevin_hours = normalize_hours(kevin_hours_raw)

    if michael_ts >= 1:
        score += 10
        feedback_parts.append(f"PASS Michael Thompson has timesheet for Apr 7-11 (+10)")
    else:
        feedback_parts.append(f"FAIL Michael Thompson has no timesheet for Apr 7-11 (+0)")

    if michael_hours >= 8:
        score += 10
        feedback_parts.append(f"PASS Michael Thompson logged {michael_hours:.1f}h (>= 8h) (+10)")
    elif michael_hours > 0:
        score += 5
        feedback_parts.append(f"PARTIAL Michael Thompson logged {michael_hours:.1f}h (some hours) (+5)")
    else:
        feedback_parts.append(f"FAIL Michael Thompson logged 0 hours (+0)")

    if kevin_ts >= 1:
        score += 10
        feedback_parts.append(f"PASS Kevin Hernandez has timesheet for Apr 7-11 (+10)")
    else:
        feedback_parts.append(f"FAIL Kevin Hernandez has no timesheet for Apr 7-11 (+0)")

    if kevin_hours >= 8:
        score += 10
        feedback_parts.append(f"PASS Kevin Hernandez logged {kevin_hours:.1f}h (>= 8h) (+10)")
    elif kevin_hours > 0:
        score += 5
        feedback_parts.append(f"PARTIAL Kevin Hernandez logged {kevin_hours:.1f}h (some hours) (+5)")
    else:
        feedback_parts.append(f"FAIL Kevin Hernandez logged 0 hours (+0)")

    score = min(score, 100)
    passed = score >= 65

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
