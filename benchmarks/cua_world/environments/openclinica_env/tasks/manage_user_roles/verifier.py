#!/usr/bin/env python3
"""Verifier for manage_user_roles task."""

import json
import tempfile
import os
import logging
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from vlm_utils import query_vlm as _query_vlm_direct

logger = logging.getLogger(__name__)


def _build_vlm_prompt():
    return """Examine this screenshot of OpenClinica (a clinical trial management system).

Check the following:
1. Is OpenClinica visible in Firefox (not an error page, login page, or blank page)?
2. Is there a user management page, user list, or role assignment page visible?
3. Can you see any usernames such as 'mrivera', 'lchang', or 'kpatel', or role labels like 'monitor', 'investigator'?
4. Is there a success message, confirmation banner, or indication that a user/role change was saved?
5. Does the page show a study user role management section or user administration area?

Respond in JSON format:
{
    "openclinica_visible": true/false,
    "user_management_visible": true/false,
    "user_or_role_visible": true/false,
    "success_message_visible": true/false,
    "confidence": "low"/"medium"/"high"
}
"""


def _verify_with_vlm(screenshot_path, query_vlm_func):
    if not query_vlm_func:
        return {"success": False, "error": "VLM not available"}
    if not os.path.exists(screenshot_path):
        return {"success": False, "error": f"Screenshot not found: {screenshot_path}"}

    vlm_result = query_vlm_func(prompt=_build_vlm_prompt(), image=screenshot_path)
    if not vlm_result.get("success"):
        return {"success": False, "error": vlm_result.get("error", "VLM query failed")}

    parsed = vlm_result.get("parsed", {})
    return {
        "success": True,
        "openclinica_visible": parsed.get("openclinica_visible", False),
        "user_management_visible": parsed.get("user_management_visible", False),
        "user_or_role_visible": parsed.get("user_or_role_visible", False),
        "success_message_visible": parsed.get("success_message_visible", False),
        "confidence": parsed.get("confidence", "low"),
    }


def _safe_int(value, default=0):
    """Safely convert a value to int."""
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        try:
            return int(value.strip())
        except (ValueError, AttributeError):
            return default
    return default


def _role_contains(role_name, target):
    """Case-insensitive check if target string appears in role_name."""
    if not role_name:
        return False
    return target.lower() in role_name.lower()


def verify_manage_user_roles(traj, env_info, task_info):
    """Verify that all user role management changes were completed in OpenClinica."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ── Load result file ───────────────────────────────────────────────────────

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/manage_user_roles_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # ── Verify result integrity via nonce ──────────────────────────────────────

    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
    except Exception:
        expected_nonce = ""
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    result_nonce = result.get('result_nonce', '')
    if expected_nonce and result_nonce != expected_nonce:
        return {
            "passed": False,
            "score": 0,
            "feedback": "INTEGRITY FAIL: Result file nonce mismatch — possible tampering",
        }

    score = 0
    feedback_parts = []

    # ── Criterion 1: mrivera DM Trial role changed to 'monitor' (20 pts) ──────

    subtask1 = result.get('subtask1_mrivera_dm', {})
    mrivera_dm_role = subtask1.get('role_name', '')
    mrivera_dm_is_monitor = subtask1.get('is_monitor', False)

    if mrivera_dm_is_monitor or _role_contains(mrivera_dm_role, 'monitor'):
        score += 20
        feedback_parts.append(f"PASS (20/20): mrivera DM Trial role is now 'monitor' (was: '{mrivera_dm_role}')")
    elif mrivera_dm_role:
        feedback_parts.append(
            f"FAIL (0/20): mrivera DM Trial role is '{mrivera_dm_role}', expected 'monitor'"
        )
    else:
        feedback_parts.append("FAIL (0/20): mrivera has no active role in DM Trial")

    # ── Criterion 2: lchang has no active role in CV Registry (20 pts) ────────

    subtask2 = result.get('subtask2_lchang_cv', {})
    lchang_cv_active = _safe_int(subtask2.get('active_role_count', 1))
    lchang_removed = subtask2.get('access_removed', False)

    if lchang_removed or lchang_cv_active == 0:
        score += 20
        feedback_parts.append("PASS (20/20): lchang has no active role in CV Registry")
    else:
        feedback_parts.append(
            f"FAIL (0/20): lchang still has {lchang_cv_active} active role(s) in CV Registry"
        )

    # ── Criterion 3: kpatel user account exists (25 pts) ──────────────────────

    subtask3 = result.get('subtask3_kpatel_user', {})
    kpatel_exists = subtask3.get('exists', False)

    if kpatel_exists:
        # Full 25 pts for existence, with sub-credit breakdown in feedback
        kpatel_first = subtask3.get('first_name', '')
        kpatel_last = subtask3.get('last_name', '')
        kpatel_email = subtask3.get('email', '')
        kpatel_affiliation = subtask3.get('institutional_affiliation', '')

        detail_parts = []
        if kpatel_first.lower() == 'kavya':
            detail_parts.append("first_name correct")
        else:
            detail_parts.append(f"first_name='{kpatel_first}' (expected 'Kavya')")

        if kpatel_last.lower() == 'patel':
            detail_parts.append("last_name correct")
        else:
            detail_parts.append(f"last_name='{kpatel_last}' (expected 'Patel')")

        if 'k.patel@clinical-research.org' in kpatel_email.lower():
            detail_parts.append("email correct")
        else:
            detail_parts.append(f"email='{kpatel_email}' (expected 'k.patel@clinical-research.org')")

        if 'stanford' in kpatel_affiliation.lower():
            detail_parts.append("affiliation correct")
        else:
            detail_parts.append(f"affiliation='{kpatel_affiliation}' (expected 'Stanford Medical Center')")

        score += 25
        feedback_parts.append(
            f"PASS (25/25): kpatel user exists — {'; '.join(detail_parts)}"
        )
    else:
        feedback_parts.append("FAIL (0/25): kpatel user account does NOT exist in the database")

    # ── Criterion 4: kpatel has 'investigator' role in DM Trial (20 pts) ──────

    subtask4 = result.get('subtask4_kpatel_dm_role', {})
    kpatel_dm_role = subtask4.get('role_name', '')
    kpatel_is_investigator = subtask4.get('is_investigator', False)

    if kpatel_is_investigator or _role_contains(kpatel_dm_role, 'investigator'):
        score += 20
        feedback_parts.append(
            f"PASS (20/20): kpatel has 'investigator' role in DM Trial (stored as: '{kpatel_dm_role}')"
        )
    elif kpatel_dm_role:
        feedback_parts.append(
            f"FAIL (0/20): kpatel DM Trial role is '{kpatel_dm_role}', expected 'investigator'"
        )
    else:
        feedback_parts.append("FAIL (0/20): kpatel has no active role in DM Trial")

    # ── Criterion 5: mrivera has 'monitor' role in AP Pilot (15 pts) ──────────

    subtask5 = result.get('subtask5_mrivera_ap', {})
    mrivera_ap_role = subtask5.get('role_name', '')
    mrivera_ap_is_monitor = subtask5.get('is_monitor', False)
    mrivera_ap_active_count = _safe_int(subtask5.get('active_role_count', 0))

    if mrivera_ap_is_monitor or _role_contains(mrivera_ap_role, 'monitor'):
        score += 15
        feedback_parts.append(
            f"PASS (15/15): mrivera has 'monitor' role in AP Pilot (stored as: '{mrivera_ap_role}')"
        )
    elif mrivera_ap_active_count > 0 and mrivera_ap_role:
        feedback_parts.append(
            f"FAIL (0/15): mrivera AP Pilot role is '{mrivera_ap_role}', expected 'monitor'"
        )
    else:
        feedback_parts.append("FAIL (0/15): mrivera has no active role in AP Pilot")

    # ── VLM visual check (up to 10 pts) ───────────────────────────────────────

    query_vlm_func = env_info.get('query_vlm')
    vlm_score = 0
    temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        copy_from_env("/tmp/task_end_screenshot.png", temp_screenshot.name)
        vlm_result = _verify_with_vlm(temp_screenshot.name, query_vlm_func)

        if vlm_result.get("success"):
            # 5 pts for user management UI visible
            if vlm_result.get("user_management_visible") or vlm_result.get("user_or_role_visible"):
                vlm_score += 5
            # 5 pts for success indication or recognized user/role names
            if vlm_result.get("success_message_visible") or (
                vlm_result.get("user_or_role_visible") and vlm_result.get("openclinica_visible")
            ):
                vlm_score += 5
            feedback_parts.append(
                f"VLM visual check: {vlm_score}/10 (confidence: {vlm_result.get('confidence', 'n/a')})"
            )
        else:
            feedback_parts.append(f"VLM unavailable: 0/10")
    except Exception as e:
        feedback_parts.append(f"VLM check failed ({e}): 0/10")
    finally:
        if os.path.exists(temp_screenshot.name):
            os.unlink(temp_screenshot.name)

    score += vlm_score

    # ── Audit log penalty: -20 if no GUI interaction detected ─────────────────

    audit_count = _safe_int(result.get('audit_log_count', 0))
    audit_baseline = _safe_int(result.get('audit_baseline_count', 0))
    audit_delta = audit_count - audit_baseline

    if audit_delta > 0:
        feedback_parts.append(
            f"GUI audit log: {audit_delta} new entries since setup (GUI interaction confirmed)"
        )
    else:
        score = max(0, score - 20)
        feedback_parts.append(
            "PENALTY (-20): No new audit log entries since setup — possible direct DB bypass without GUI"
        )

    # ── Pass/fail determination (threshold: 70 pts) ────────────────────────────

    # Core subtasks must pass for overall pass
    core_subtasks_passed = (
        (mrivera_dm_is_monitor or _role_contains(mrivera_dm_role, 'monitor'))
        and (lchang_removed or lchang_cv_active == 0)
        and kpatel_exists
        and (kpatel_is_investigator or _role_contains(kpatel_dm_role, 'investigator'))
        and (mrivera_ap_is_monitor or _role_contains(mrivera_ap_role, 'monitor'))
    )

    passed = score >= 70 and core_subtasks_passed

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
