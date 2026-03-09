#!/usr/bin/env python3
"""
Verifier for access_control_restructure task.

Scenario: Security Management Specialist enforcing new access control policy.
Three independent subtasks:
  1. Delete former employees john.smith and sarah.jones
  2. Create external auditor account ext.auditor
  3. Create 'Audit Trail View' layout with Entrance + Server Room cameras

Scoring (100 points):
  - john.smith account deleted                                      : 20 pts
  - sarah.jones account deleted                                     : 20 pts
  - ext.auditor account created with correct email and full name    : 30 pts
  - 'Audit Trail View' layout created with both required cameras    : 30 pts

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/access_control_restructure_result.json"


def verify_access_control_restructure(traj, env_info, task_info):
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

    user_check = result.get("user_check", {})
    layout_check = result.get("layout_check", {})

    # --- Subtask 1: john.smith deleted ---
    if not user_check.get("john_smith_exists", True):
        score += 20
        feedback_parts.append("john.smith account deleted (20/20)")
    else:
        feedback_parts.append("john.smith account still exists — NOT deleted (0/20)")

    # --- Subtask 2: sarah.jones deleted ---
    if not user_check.get("sarah_jones_exists", True):
        score += 20
        feedback_parts.append("sarah.jones account deleted (20/20)")
    else:
        feedback_parts.append("sarah.jones account still exists — NOT deleted (0/20)")

    # --- Subtask 3: ext.auditor created with correct info ---
    ext_exists = user_check.get("ext_auditor_exists", False)
    ext_email = user_check.get("ext_auditor_email", "").lower().strip()
    ext_fullname = user_check.get("ext_auditor_fullname", "").lower().strip()
    expected_email = "auditor@thirdparty-sec.com"
    expected_fullname = "external security auditor"

    if ext_exists and ext_email == expected_email and ext_fullname == expected_fullname:
        score += 30
        feedback_parts.append(
            f"ext.auditor created with correct email and full name (30/30)"
        )
    elif ext_exists and ext_email == expected_email:
        score += 22
        feedback_parts.append(
            f"ext.auditor created with correct email but full name mismatch "
            f"(got '{user_check.get('ext_auditor_fullname','')}') (22/30)"
        )
    elif ext_exists:
        score += 15
        feedback_parts.append(
            f"ext.auditor account created but email incorrect "
            f"(got '{user_check.get('ext_auditor_email','')}', expected '{expected_email}') (15/30)"
        )
    else:
        feedback_parts.append("ext.auditor account NOT created (0/30)")

    # --- Subtask 4: Layout 'Audit Trail View' with both cameras ---
    layout_found = layout_check.get("layout_found", False)
    cameras_matched = layout_check.get("cameras_matched", 0)

    if layout_found and cameras_matched >= 2:
        score += 30
        feedback_parts.append(
            "'Audit Trail View' layout created with both required cameras (30/30)"
        )
    elif layout_found and cameras_matched == 1:
        score += 15
        feedback_parts.append(
            "'Audit Trail View' layout exists but only 1 of 2 required cameras present (15/30)"
        )
    elif layout_found:
        score += 7
        feedback_parts.append(
            "'Audit Trail View' layout exists but contains no recognized cameras (7/30)"
        )
    else:
        feedback_parts.append("'Audit Trail View' layout NOT created (0/30)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
    }
