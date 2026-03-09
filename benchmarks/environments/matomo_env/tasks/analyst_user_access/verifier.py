#!/usr/bin/env python3
"""
Verifier for Analyst User Access task.

Occupation: Marketing Manager
Task: Create user jamie.rodriguez, grant view access to 2 of 4 sites, create monthly report.

Scoring (100 points):
- User jamie.rodriguez created (new during task):  20 pts  (gate: 0 if not new)
- 'view' access to Main Store:                     15 pts
- 'view' access to Blog:                           15 pts
- NO access to Mobile App:                         15 pts
- NO access to Confidential Data:                  15 pts
- Monthly email report exists for jamie.rodriguez: 20 pts

Pass threshold: >= 70 points AND user was newly created.
"""

import json
import logging
import os
import tempfile
from typing import Any, Dict

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

EXPECTED_LOGIN = "jamie.rodriguez"
EXPECTED_EMAIL = "jamie.rodriguez@company.test"
EXPECTED_PERIOD = "month"


def verify_analyst_user_access(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify user creation, access control, and monthly report."""

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        try:
            copy_from_env("/tmp/analyst_user_access_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {
            "passed": False, "score": 0,
            "feedback": "Result file not found — export script may not have run",
        }
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid result JSON: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error: {e}"}

    score = 0
    feedback = []
    subscores: Dict[str, bool] = {}

    user_exists = str(result.get("user_exists", "false")).lower() == "true"
    user_is_new = str(result.get("user_is_new", "false")).lower() == "true"
    user_email = str(result.get("user_email", "")).strip().lower()
    access = result.get("access", {})
    report = result.get("report", {})

    logger.info("user_exists=%s user_is_new=%s email=%s", user_exists, user_is_new, user_email)
    logger.info("access=%s report=%s", access, report)

    # ── GATE: user must be newly created ─────────────────────────────────
    if not user_is_new:
        msg = (
            "User 'jamie.rodriguez' was not created during this task (or did not exist at all). "
            "Anti-gaming gate triggered → score=0."
        ) if not user_exists else (
            "User 'jamie.rodriguez' pre-existed before task started. "
            "Anti-gaming gate triggered → score=0."
        )
        return {
            "passed": False, "score": 0,
            "feedback": msg,
            "subscores": subscores,
        }

    # ── Criterion 1: user created with correct email (20 pts) ─────────────
    email_ok = user_email == EXPECTED_EMAIL.lower()
    if user_exists and email_ok:
        score += 20
        subscores["user_created"] = True
        feedback.append(f"User {EXPECTED_LOGIN} created with correct email [+20]")
    elif user_exists:
        score += 10  # partial credit: user exists but wrong email
        subscores["user_created"] = False
        feedback.append(
            f"User {EXPECTED_LOGIN} exists but wrong email: "
            f"expected '{EXPECTED_EMAIL}', got '{user_email}' [+10 partial]"
        )
    else:
        subscores["user_created"] = False
        feedback.append(f"User {EXPECTED_LOGIN} NOT found in database [-20]")

    # ── Criterion 2: view access to Main Store (15 pts) ──────────────────
    main_access = str(access.get("main_store", "none")).lower().strip()
    if main_access == "view":
        score += 15
        subscores["view_access_main_store"] = True
        feedback.append("Has 'view' access to Main Store [+15]")
    else:
        subscores["view_access_main_store"] = False
        feedback.append(f"Main Store access: expected 'view', got '{main_access}' [-15]")

    # ── Criterion 3: view access to Blog (15 pts) ────────────────────────
    blog_access = str(access.get("blog", "none")).lower().strip()
    if blog_access == "view":
        score += 15
        subscores["view_access_blog"] = True
        feedback.append("Has 'view' access to Blog [+15]")
    else:
        subscores["view_access_blog"] = False
        feedback.append(f"Blog access: expected 'view', got '{blog_access}' [-15]")

    # ── Criterion 4: NO access to Mobile App (15 pts) ────────────────────
    mobile_access = str(access.get("mobile_app", "none")).lower().strip()
    if mobile_access in ("none", ""):
        score += 15
        subscores["no_access_mobile_app"] = True
        feedback.append("No access to Mobile App ✓ [+15]")
    else:
        subscores["no_access_mobile_app"] = False
        feedback.append(
            f"Mobile App access should be NONE, got '{mobile_access}' (security violation) [-15]"
        )

    # ── Criterion 5: NO access to Confidential Data (15 pts) ─────────────
    conf_access = str(access.get("confidential", "none")).lower().strip()
    if conf_access in ("none", ""):
        score += 15
        subscores["no_access_confidential"] = True
        feedback.append("No access to Confidential Data ✓ [+15]")
    else:
        subscores["no_access_confidential"] = False
        feedback.append(
            f"Confidential Data access should be NONE, got '{conf_access}' (security violation) [-15]"
        )

    # ── Criterion 6: Monthly report (20 pts) ─────────────────────────────
    report_exists = str(report.get("exists", "false")).lower() == "true"
    report_period = str(report.get("period", "")).lower().strip()
    if report_exists and report_period == EXPECTED_PERIOD:
        score += 20
        subscores["monthly_report_exists"] = True
        feedback.append(f"Monthly email report configured for {EXPECTED_LOGIN} on Main Store [+20]")
    elif report_exists:
        score += 10  # partial credit: report exists but wrong period
        subscores["monthly_report_exists"] = False
        feedback.append(
            f"Report exists but period is '{report_period}' (expected 'month') [+10 partial]"
        )
    else:
        subscores["monthly_report_exists"] = False
        feedback.append(f"No email report found for {EXPECTED_LOGIN} [-20]")

    passed = score >= 70 and user_is_new

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "details": {
            "user_email": user_email,
            "access": access,
            "report": report,
        },
    }
