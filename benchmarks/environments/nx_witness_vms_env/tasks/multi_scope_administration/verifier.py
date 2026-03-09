#!/usr/bin/env python3
"""
Verifier for multi_scope_administration task.

Scenario: VMS administrator onboarding new retail client — 4 independent subtasks
across 4 different system areas (system settings, layout×2, user management).

Scoring (100 points):
  - System name changed to 'RetailSecure Pro'                        : 20 pts
  - 'Perimeter Surveillance' layout with Parking Lot + Entrance cams : 25 pts
  - 'Infrastructure Monitoring' layout with Server Room cam only     : 25 pts
  - vendor.tech user created with correct email and full name        : 30 pts

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/multi_scope_administration_result.json"
TARGET_SYSTEM_NAME = "retailsecure pro"
TARGET_USER_EMAIL = "tech@vendor-security.com"
TARGET_USER_FULLNAME = "vendor technical support"


def verify_multi_scope_administration(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env(RESULT_PATH, tmp.name)
            with open(tmp.name, "r") as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export script may not have run",
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []

    # --- Subtask 1: System name renamed ---
    actual_name = result.get("system_name", "").strip().lower()
    if actual_name == TARGET_SYSTEM_NAME:
        score += 20
        feedback_parts.append("System renamed to 'RetailSecure Pro' (20/20)")
    elif "retailsecure" in actual_name or "retail secure" in actual_name:
        score += 14
        feedback_parts.append(
            f"System name close match '{result.get('system_name','')}' "
            f"(expected 'RetailSecure Pro') (14/20)"
        )
    else:
        feedback_parts.append(
            f"System name NOT changed — still '{result.get('system_name', '')}' (0/20)"
        )

    # --- Subtask 2: 'Perimeter Surveillance' layout ---
    lr = result.get("layout_results", {})
    peri_found = lr.get("perimeter_found", False)
    peri_parking = lr.get("perimeter_has_parking", False)
    peri_entrance = lr.get("perimeter_has_entrance", False)

    if peri_found and peri_parking and peri_entrance:
        score += 25
        feedback_parts.append(
            "'Perimeter Surveillance' layout with Parking Lot + Entrance Camera (25/25)"
        )
    elif peri_found and (peri_parking or peri_entrance):
        missing = []
        if not peri_parking:
            missing.append("Parking Lot Camera")
        if not peri_entrance:
            missing.append("Entrance Camera")
        score += 12
        feedback_parts.append(
            f"'Perimeter Surveillance' exists but missing: {', '.join(missing)} (12/25)"
        )
    elif peri_found:
        score += 5
        feedback_parts.append(
            "'Perimeter Surveillance' layout exists but contains no required cameras (5/25)"
        )
    else:
        feedback_parts.append("'Perimeter Surveillance' layout NOT created (0/25)")

    # --- Subtask 3: 'Infrastructure Monitoring' layout ---
    infra_found = lr.get("infra_found", False)
    infra_server = lr.get("infra_has_server", False)

    if infra_found and infra_server:
        score += 25
        feedback_parts.append(
            "'Infrastructure Monitoring' layout with Server Room Camera (25/25)"
        )
    elif infra_found:
        score += 10
        feedback_parts.append(
            "'Infrastructure Monitoring' layout exists but Server Room Camera missing (10/25)"
        )
    else:
        feedback_parts.append("'Infrastructure Monitoring' layout NOT created (0/25)")

    # --- Subtask 4: vendor.tech user created ---
    vendor = result.get("vendor_tech_user", {})
    v_exists = vendor.get("exists", False)
    v_email = (vendor.get("email") or "").lower().strip()
    v_fullname = (vendor.get("fullname") or "").lower().strip()

    if v_exists and v_email == TARGET_USER_EMAIL and v_fullname == TARGET_USER_FULLNAME:
        score += 30
        feedback_parts.append(
            "vendor.tech user created with correct email and full name (30/30)"
        )
    elif v_exists and v_email == TARGET_USER_EMAIL:
        score += 22
        feedback_parts.append(
            f"vendor.tech created, email correct, but full name mismatch "
            f"(got '{vendor.get('fullname','')}') (22/30)"
        )
    elif v_exists:
        score += 15
        feedback_parts.append(
            f"vendor.tech account created but email incorrect "
            f"(got '{vendor.get('email','')}', expected '{TARGET_USER_EMAIL}') (15/30)"
        )
    else:
        feedback_parts.append("vendor.tech account NOT created (0/30)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
    }
