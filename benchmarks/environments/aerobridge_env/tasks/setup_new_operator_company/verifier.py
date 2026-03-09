#!/usr/bin/env python3
"""Verifier for setup_new_operator_company task.

Checks that the agent created a new Company 'BlueSky Robotics Pvt Ltd'
and linked a new Operator to it with correct attributes.

Scoring (100 points total):
  - Company 'BlueSky Robotics Pvt Ltd' exists:    20 pts
  - Company role == Operator (2):                 15 pts
  - Company country == IN (India):                15 pts
  - Operator record linked to company exists:     25 pts
  - Operator has at least one activity/auth:      25 pts

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

EXPECTED_COMPANY_NAME = "BlueSky Robotics Pvt Ltd"
EXPECTED_ROLE = 2   # Operator
EXPECTED_COUNTRY = "IN"


def verify_setup_new_operator_company(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp_path = tmp.name
    tmp.close()
    try:
        copy_from_env("/tmp/setup_new_operator_company_result.json", tmp_path)
        with open(tmp_path) as f:
            data = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found in VM. Export script may not have run."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass

    if data.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Export error: {data['error']}"}

    score = 0
    feedback_parts = []
    comp = data.get("company")
    op = data.get("operator")

    # ── Check 1: Company exists with correct name (20 pts) ────────────────────
    if comp and comp.get("full_name", "").strip().lower() == EXPECTED_COMPANY_NAME.lower():
        score += 20
        feedback_parts.append(f"✓ Company '{EXPECTED_COMPANY_NAME}' created (+20)")
    elif comp:
        score += 10
        feedback_parts.append(
            f"~ Company found but name mismatch: '{comp.get('full_name')}' (+10)"
        )
    else:
        feedback_parts.append(f"✗ Company '{EXPECTED_COMPANY_NAME}' not found")

    # ── Check 2: Company role == Operator (2) (15 pts) ────────────────────────
    if comp:
        role = comp.get("role")
        if role == EXPECTED_ROLE:
            score += 15
            feedback_parts.append("✓ Company role is 'Operator' (2) (+15)")
        else:
            role_names = {0: "Manufacturer", 1: "Manufacturer and Operator", 2: "Operator", 3: "Other"}
            feedback_parts.append(
                f"✗ Company role is '{role_names.get(role, role)}' ({role}), expected 'Operator' (2)"
            )

    # ── Check 3: Company country == IN (15 pts) ───────────────────────────────
    if comp:
        country = comp.get("country", "")
        if country.strip().upper() == EXPECTED_COUNTRY:
            score += 15
            feedback_parts.append("✓ Company country is 'IN' (India) (+15)")
        else:
            feedback_parts.append(
                f"✗ Company country is '{country}', expected 'IN' (India)"
            )

    # ── Check 4: Operator record linked to BlueSky exists (25 pts) ───────────
    if op:
        if op.get("company_full_name", "").strip().lower() == EXPECTED_COMPANY_NAME.lower():
            score += 25
            feedback_parts.append("✓ Operator record linked to BlueSky Robotics created (+25)")
        else:
            score += 10
            feedback_parts.append(
                f"~ Operator exists but linked to '{op.get('company_full_name')}', not BlueSky (+10)"
            )
    else:
        feedback_parts.append("✗ No Operator record linked to BlueSky Robotics found")

    # ── Check 5: Operator has at least one activity or authorization (25 pts) ─
    if op:
        activities = op.get("authorized_activities", [])
        auths = op.get("operational_authorizations", [])
        if activities or auths:
            score += 25
            feedback_parts.append(
                f"✓ Operator has activities={activities} and/or authorizations={auths} (+25)"
            )
        else:
            feedback_parts.append(
                "✗ Operator has no authorized_activities and no operational_authorizations set"
            )

    passed = score >= 60
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\nTotal score: {score}/100 ({'PASSED' if passed else 'FAILED'}, threshold 60)"

    return {"passed": passed, "score": score, "feedback": feedback}
