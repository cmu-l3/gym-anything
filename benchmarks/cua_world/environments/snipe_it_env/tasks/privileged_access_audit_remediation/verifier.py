#!/usr/bin/env python3
"""
Verifier for privileged_access_audit_remediation task.

Scoring breakdown (100 points):
  C1: Privilege Revocation (24 pts) — 8 pts per non-IT manager stripped of superuser.
  C2: Group Assignment (15 pts) — 5 pts per non-IT manager added to "Department Managers".
  C3: Precision (16 pts) — 8 pts per legitimate IT Admin (admin, jdoe) retaining superuser.
      CRITICAL: If an IT Admin loses superuser access, total score is capped at 40 (Fail).
  C4: Asset Recovery (15 pts) — ASSET-EXT-01 checked in and "Ready to Deploy".
  C5: Account Deactivation (15 pts) — evance activated=0 but NOT deleted.
  C6: Audit Report (15 pts) — Report contains exactly asmith, bjones, cwilliams.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/privileged_access_audit_remediation_result.json"


def verify_privileged_access_audit_remediation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(RESULT_PATH, temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found in VM."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    users = result.get("users", {})
    asset = result.get("asset", {})
    report = result.get("report", [])

    violating_managers = ["asmith", "bjones", "cwilliams"]
    control_admins = ["admin", "jdoe"]

    # --- Do-Nothing Gate ---
    managers_changed = any(not users.get(m, {}).get("is_superuser", True) for m in violating_managers)
    evance_deactivated = not users.get("evance", {}).get("activated", True)
    asset_recovered = asset.get("is_checked_in", False)
    report_created = len(report) > 0

    if not (managers_changed or evance_deactivated or asset_recovered or report_created):
        return {"passed": False, "score": 0, "feedback": "DO-NOTHING: No remediation actions taken."}

    # --- C1: Privilege Revocation (24 points) ---
    c1_score = 0
    for m in violating_managers:
        u_data = users.get(m, {})
        if u_data and not u_data.get("is_superuser", True):
            c1_score += 8
        else:
            feedback.append(f"C1: {m} still retains superuser privileges.")
    score += c1_score
    if c1_score == 24:
        feedback.append("C1: All non-IT managers successfully stripped of superuser (+24)")

    # --- C2: Group Assignment (15 points) ---
    c2_score = 0
    for m in violating_managers:
        u_data = users.get(m, {})
        if u_data and u_data.get("in_mgr_group", False):
            c2_score += 5
        else:
            feedback.append(f"C2: {m} not assigned to 'Department Managers' group.")
    score += c2_score
    if c2_score == 15:
        feedback.append("C2: All non-IT managers assigned to correct group (+15)")

    # --- C3: Precision / Control Group (16 points) ---
    c3_score = 0
    admin_locked_out = False
    for a in control_admins:
        u_data = users.get(a, {})
        if u_data and u_data.get("is_superuser", False):
            c3_score += 8
        else:
            admin_locked_out = True
            feedback.append(f"C3: CRITICAL ERROR - Legitimate admin '{a}' lost superuser access!")
    score += c3_score
    if c3_score == 16:
        feedback.append("C3: Legitimate IT Admins retained their access (+16)")

    # --- C4: Asset Recovery (15 points) ---
    if asset.get("found"):
        if asset.get("is_checked_in") and asset.get("is_ready"):
            score += 15
            feedback.append("C4: ASSET-EXT-01 checked in and 'Ready to Deploy' (+15)")
        else:
            feedback.append("C4: ASSET-EXT-01 is either not checked in or not 'Ready to Deploy'.")
    else:
        feedback.append("C4: ASSET-EXT-01 not found.")

    # --- C5: Account Deactivation (15 points) ---
    evance = users.get("evance", {})
    if evance:
        if not evance.get("activated", True) and not evance.get("is_deleted", True):
            score += 15
            feedback.append("C5: Contractor 'evance' deactivated successfully without deletion (+15)")
        elif evance.get("is_deleted", False):
            feedback.append("C5: Contractor 'evance' was deleted. Audit policy requires deactivation only.")
        else:
            feedback.append("C5: Contractor 'evance' account is still active.")
    else:
        feedback.append("C5: Contractor 'evance' user record missing entirely.")

    # --- C6: Audit Report (15 points) ---
    expected_report_users = set(violating_managers)
    actual_report_users = set(name.strip().lower() for name in report)
    
    if len(actual_report_users) > 0:
        if actual_report_users == expected_report_users:
            score += 15
            feedback.append("C6: Remediation report contains exactly the correct usernames (+15)")
        else:
            feedback.append(f"C6: Remediation report incorrect. Expected {expected_report_users}, got {actual_report_users}")
    else:
        feedback.append("C6: Remediation report missing or empty.")

    # --- Final Score Resolution ---
    if admin_locked_out:
        score = min(score, 40)
        feedback.append("CRITICAL PENALTY: Task failed because legitimate IT Admins were locked out. Score capped at 40.")

    passed = score >= 80 and not admin_locked_out

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }