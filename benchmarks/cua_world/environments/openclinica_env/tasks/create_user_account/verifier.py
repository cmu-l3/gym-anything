#!/usr/bin/env python3
"""Verifier for create_user_account task."""

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
2. Is there a success message or confirmation that a user account was created?
3. Can you see a username like 'jsmith' or a name like 'John Smith' in any list or confirmation?
4. Does the page show a user list, user details, or a "user created" confirmation?

Respond in JSON format:
{
    "openclinica_visible": true/false,
    "success_message_visible": true/false,
    "user_name_visible": true/false,
    "user_list_or_details_visible": true/false,
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
        "success_message_visible": parsed.get("success_message_visible", False),
        "user_name_visible": parsed.get("user_name_visible", False),
        "user_list_or_details_visible": parsed.get("user_list_or_details_visible", False),
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


def verify_create_user_account(traj, env_info, task_info):
    """Verify that a user account was created in OpenClinica."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_username = metadata.get('expected_username', 'jsmith')
    expected_first = metadata.get('expected_first_name', 'John')
    expected_last = metadata.get('expected_last_name', 'Smith')
    expected_email = metadata.get('expected_email', 'jsmith@clinic.org')
    expected_role = metadata.get('expected_role', 'clinical research coordinator')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_user_account_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Verify result integrity via nonce
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
        return {"passed": False, "score": 0,
                "feedback": "INTEGRITY FAIL: Result file nonce mismatch — possible tampering"}

    score = 0
    feedback_parts = []

    initial_count = _safe_int(result.get('initial_user_count', 0))
    current_count = _safe_int(result.get('current_user_count', 0))
    user_found = result.get('user_found', False)
    user = result.get('user', {})

    # Criterion 1: User exists (15 points)
    if user_found:
        score += 15
        feedback_parts.append("User found in database")
    else:
        feedback_parts.append("FAIL: User NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Username matches (15 points)
    username = user.get('username', '').strip()
    if username.lower() == expected_username.lower():
        score += 15
        feedback_parts.append(f"Username correct: {username}")
    elif 'smith' in username.lower() or 'jsmith' in username.lower():
        score += 5
        feedback_parts.append(f"Username partially matches: '{username}'")
    else:
        feedback_parts.append(f"Username mismatch: expected '{expected_username}', got '{username}'")

    # Criterion 3: Name correct (10 points)
    first = user.get('first_name', '').strip()
    last = user.get('last_name', '').strip()
    if first.lower() == expected_first.lower() and last.lower() == expected_last.lower():
        score += 10
        feedback_parts.append(f"Name correct: {first} {last}")
    elif first or last:
        score += 2
        feedback_parts.append(f"Name set: {first} {last}")
    else:
        feedback_parts.append("FAIL: Name not set")

    # Criterion 4: Email correct (10 points)
    email = user.get('email', '').strip()
    if email.lower() == expected_email.lower():
        score += 10
        feedback_parts.append(f"Email correct: {email}")
    elif '@' in email:
        score += 2
        feedback_parts.append(f"Email set but different: '{email}'")
    else:
        feedback_parts.append("FAIL: Email not set")

    # Criterion 5: Role assigned (10 points)
    # OpenClinica DB stores roles with underscores (e.g. 'clinical_research_coordinator')
    # while display names use spaces. Accept both formats at full points.
    role = user.get('role', '').strip().lower()
    role_normalized = role.replace('_', ' ')
    if role_normalized == expected_role.lower() or role == expected_role.lower():
        score += 10
        feedback_parts.append(f"Role correct: {user.get('role', '')}")
    elif 'coordinator' in role:
        score += 3
        feedback_parts.append(f"Role contains 'coordinator' but not exact: '{role}'")
    elif role:
        score += 1
        feedback_parts.append(f"Role assigned but different: '{role}'")
    else:
        feedback_parts.append("FAIL: No role assigned")

    # Criterion 6: Role assigned to correct study (5 points)
    role_in_correct_study = user.get('role_in_correct_study', False)
    if role_in_correct_study:
        score += 5
        feedback_parts.append("Role assigned to correct study (Phase II Diabetes Trial)")
    elif role:
        feedback_parts.append("Role assigned but not to the expected study")
    else:
        feedback_parts.append("No role — cannot check study assignment")

    # Criterion 7: Institutional affiliation (5 points)
    expected_affiliation = metadata.get('expected_affiliation', 'City General Hospital')
    affiliation = user.get('affiliation', '').strip()
    if affiliation.lower() == expected_affiliation.lower():
        score += 5
        feedback_parts.append(f"Affiliation correct: {affiliation}")
    elif affiliation:
        score += 2
        feedback_parts.append(f"Affiliation set but different: '{affiliation}'")
    else:
        feedback_parts.append("Affiliation not set")

    # Criterion 8: Newly created (5 points)
    if current_count > initial_count:
        score += 5
        feedback_parts.append("User count increased")
    else:
        feedback_parts.append("User count unchanged")

    # Criterion 9: VLM visual verification (20 points)
    query_vlm_func = env_info.get('query_vlm')
    vlm_score = 0
    temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        copy_from_env("/tmp/task_end_screenshot.png", temp_screenshot.name)
        vlm_result = _verify_with_vlm(temp_screenshot.name, query_vlm_func)

        if vlm_result.get("success"):
            if vlm_result.get("success_message_visible") or vlm_result.get("user_list_or_details_visible"):
                vlm_score += 10
            if vlm_result.get("user_name_visible"):
                vlm_score += 10
            feedback_parts.append(f"VLM visual check: {vlm_score}/20 (confidence: {vlm_result.get('confidence', 'n/a')})")
        else:
            vlm_score = 0
            feedback_parts.append(f"VLM unavailable: {vlm_score}/20")
    except Exception as e:
        vlm_score = 0
        feedback_parts.append(f"VLM check failed ({e}): {vlm_score}/20")
    finally:
        if os.path.exists(temp_screenshot.name):
            os.unlink(temp_screenshot.name)

    score += vlm_score

    # Criterion 10: GUI interaction via audit log (25 points penalty if missing)
    audit_count = _safe_int(result.get('audit_log_count', 0))
    audit_baseline = _safe_int(result.get('audit_baseline_count', 0))
    audit_entity_count = _safe_int(result.get('audit_entity_count', 0))
    audit_delta = audit_count - audit_baseline

    gui_verified = audit_delta > 0 and audit_entity_count > 0
    if gui_verified:
        feedback_parts.append(f"GUI audit log: {audit_delta} new entries, {audit_entity_count} user-specific (GUI confirmed)")
    elif audit_delta > 0:
        gui_verified = True
        feedback_parts.append(f"GUI audit log: {audit_delta} new entries but 0 user-specific (weak GUI evidence)")
    else:
        score = max(0, score - 25)
        feedback_parts.append("PENALTY (-25): No new audit log entries since setup — possible direct SQL bypass")

    username_ok = username.lower() == expected_username.lower()
    passed = score >= 60 and user_found and username_ok and gui_verified

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
