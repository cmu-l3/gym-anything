#!/usr/bin/env python3
"""
Verifier for new_department_provisioning task.

Required actions:
  1. Create group 'Executive Operations'
  2. Create time profile 'Executive Hours' (Mon-Fri 07:00-22:00)
  3. Add IT Department members (Kwame Asante, Mei-Ling Zhang) to Executive Operations
  4. Create user Elena Vasquez with correct fields
  5. Assign Elena card 0004522050
  6. Add Elena to Executive Operations

Scoring (100 pts total, pass threshold = 70):

  A – 'Executive Operations' group exists:               15 pts
  B – 'Executive Hours' time profile exists (Mon-Fri,
      timeFrom=07:00, timeTo=22:00):                     20 pts
  C – Kwame Asante in Executive Operations:              15 pts
  D – Mei-Ling Zhang in Executive Operations:            15 pts
  E – Elena Vasquez user exists (correct name/email):    15 pts
  F – Elena has card 0004522050:                         10 pts
  G – Elena in Executive Operations:                     10 pts

  max_partial_total analysis:
    A+B+C+D+E without F,G: 15+20+15+15+15 = 80 → passes ✓
    A+B without any members: 35 < 70 ✓
    A+B+C+D: 65 < 70 ✓
    A+B+C+D+E: 80 → passes — correct, 5 of 6 steps completed
"""

import json
import os
import tempfile

WEEKDAYS = {"MON", "TUE", "WED", "THU", "FRI"}
IT_EMAILS = {"k.asante@buildingtech.com", "m.zhang@buildingtech.com"}


def _schedule_matches(schedules):
    """Return True if any schedule covers Mon-Fri 07:00-22:00."""
    for s in schedules:
        days = set(s.get("days", []))
        time_from = s.get("timeFrom", "")
        time_to   = s.get("timeTo", "")
        if WEEKDAYS.issubset(days) and time_from == "07:00" and time_to == "22:00":
            return True
    return False


def verify_new_department_provisioning(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "copy_from_env not available in env_info"}

    tmp = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env("/tmp/new_department_provisioning_result.json", tmp)
    except Exception as e:
        return {"passed": False, "score": 0,
                "feedback": f"Could not retrieve result file: {e}"}

    try:
        with open(tmp) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0,
                "feedback": f"Could not parse result JSON: {e}"}
    finally:
        try:
            os.remove(tmp)
        except Exception:
            pass

    score = 0
    feedback = []

    exec_group   = result.get("exec_group", {})
    exec_profile = result.get("exec_profile", {})
    elena        = result.get("elena", {})
    it_in_exec   = result.get("it_members_in_exec", {})

    # ── A: Executive Operations group exists ───────────────────────────────
    if exec_group.get("exists"):
        score += 15
        feedback.append("PASS: 'Executive Operations' group created (+15)")
    else:
        feedback.append("FAIL: 'Executive Operations' group does not exist")

    # ── B: Executive Hours time profile (Mon-Fri, 07:00-22:00) ────────────
    if exec_profile.get("exists"):
        schedules = exec_profile.get("schedules", [])
        if _schedule_matches(schedules):
            score += 20
            feedback.append("PASS: 'Executive Hours' time profile with Mon-Fri 07:00-22:00 (+20)")
        else:
            # Partial: profile exists but wrong schedule
            score += 8
            feedback.append(
                f"PARTIAL: 'Executive Hours' profile exists but schedule doesn't match "
                f"Mon-Fri 07:00-22:00 (found: {schedules}) (+8)"
            )
    else:
        feedback.append("FAIL: 'Executive Hours' time profile does not exist")

    # ── C: Kwame Asante in Executive Operations ────────────────────────────
    kwame_in_exec = it_in_exec.get("k.asante@buildingtech.com", False)
    if kwame_in_exec:
        score += 15
        feedback.append("PASS: Kwame Asante added to Executive Operations (+15)")
    else:
        feedback.append("FAIL: Kwame Asante is not in Executive Operations")

    # ── D: Mei-Ling Zhang in Executive Operations ──────────────────────────
    meilin_in_exec = it_in_exec.get("m.zhang@buildingtech.com", False)
    if meilin_in_exec:
        score += 15
        feedback.append("PASS: Mei-Ling Zhang added to Executive Operations (+15)")
    else:
        feedback.append("FAIL: Mei-Ling Zhang is not in Executive Operations")

    # ── E: Elena Vasquez user exists with correct data ─────────────────────
    if elena.get("exists"):
        email_ok = elena.get("email", "").lower() == "e.vasquez@buildingtech.com"
        if email_ok:
            score += 15
            feedback.append("PASS: Elena Vasquez user created with correct email (+15)")
        else:
            score += 8
            feedback.append(
                f"PARTIAL: Elena Vasquez exists but email is '{elena.get('email')}' "
                f"instead of e.vasquez@buildingtech.com (+8)"
            )
    else:
        feedback.append("FAIL: Elena Vasquez user does not exist")

    # ── F: Elena has card 0004522050 ───────────────────────────────────────
    if elena.get("has_card_0004522050"):
        score += 10
        feedback.append("PASS: Elena Vasquez assigned RFID card 0004522050 (+10)")
    else:
        feedback.append("FAIL: Elena Vasquez does not have card 0004522050")

    # ── G: Elena in Executive Operations ──────────────────────────────────
    if elena.get("in_exec_group"):
        score += 10
        feedback.append("PASS: Elena Vasquez is in Executive Operations (+10)")
    else:
        feedback.append("FAIL: Elena Vasquez is not in Executive Operations")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback),
    }
