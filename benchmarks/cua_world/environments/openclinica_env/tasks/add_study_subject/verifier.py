#!/usr/bin/env python3
"""Verifier for add_study_subject task."""

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
2. Is there a success message or confirmation that a study subject was added?
3. Can you see a subject ID like 'SS-001' in any list or confirmation message?
4. Does the page show a subject matrix, subject details, or an "added successfully" message?

Respond in JSON format:
{
    "openclinica_visible": true/false,
    "success_message_visible": true/false,
    "subject_id_visible": true/false,
    "subject_list_or_details_visible": true/false,
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
        "subject_id_visible": parsed.get("subject_id_visible", False),
        "subject_list_or_details_visible": parsed.get("subject_list_or_details_visible", False),
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


def verify_add_study_subject(traj, env_info, task_info):
    """Verify that a study subject was added in OpenClinica."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_label = metadata.get('expected_subject_id', 'SS-001')
    expected_gender = metadata.get('expected_gender', 'm')
    expected_dob = metadata.get('expected_dob', '1975-06-15')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/add_study_subject_result.json", temp_file.name)
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

    initial_count = _safe_int(result.get('initial_subject_count', 0))
    current_count = _safe_int(result.get('current_subject_count', 0))
    subject_found = result.get('subject_found', False)
    subject = result.get('subject', {})

    # Criterion 1: Subject exists (15 points)
    if subject_found:
        score += 15
        feedback_parts.append("Subject found in database")
    else:
        feedback_parts.append("FAIL: Subject NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Label matches (20 points)
    label = subject.get('label', '').strip()
    if label.lower() == expected_label.lower():
        score += 20
        feedback_parts.append(f"Subject ID correct: {label}")
    elif expected_label.lower().replace('-', '') in label.lower().replace('-', ''):
        score += 8
        feedback_parts.append(f"Subject ID partially matches: '{label}'")
    else:
        feedback_parts.append(f"FAIL: Label mismatch: expected '{expected_label}', got '{label}'")

    # Criterion 3: Gender matches (10 points)
    gender = subject.get('gender', '').strip().lower()
    if gender in (expected_gender.lower(), 'male', 'm'):
        score += 10
        feedback_parts.append(f"Gender correct: {gender}")
    else:
        feedback_parts.append(f"Gender mismatch: expected '{expected_gender}', got '{gender}'")

    # Criterion 4: DOB matches (10 points)
    dob = subject.get('date_of_birth', '').strip()
    if dob:
        try:
            from datetime import datetime
            dob_clean = dob.split('T')[0].split(' ')[0]
            expected_clean = expected_dob.split('T')[0].split(' ')[0]
            dob_date = datetime.strptime(dob_clean, '%Y-%m-%d').date()
            expected_date = datetime.strptime(expected_clean, '%Y-%m-%d').date()
            if dob_date == expected_date:
                score += 10
                feedback_parts.append(f"DOB correct: {dob}")
            elif dob_date.year == expected_date.year:
                score += 3
                feedback_parts.append(f"DOB year correct but date differs: {dob}")
            else:
                feedback_parts.append(f"DOB mismatch: expected '{expected_dob}', got '{dob}'")
        except (ValueError, IndexError):
            if expected_dob in dob:
                score += 10
                feedback_parts.append(f"DOB correct (string match): {dob}")
            else:
                feedback_parts.append(f"DOB format unrecognized: '{dob}'")
    else:
        feedback_parts.append("DOB not set")

    # Criterion 5: Enrollment date is set (5 points)
    enrollment_date = subject.get('enrollment_date', '').strip()
    if enrollment_date:
        score += 5
        feedback_parts.append(f"Enrollment date set: {enrollment_date}")
    else:
        feedback_parts.append("Enrollment date not set")

    # Criterion 6: Count increased (10 points)
    if current_count > initial_count:
        score += 10
        feedback_parts.append("Subject count increased")
    else:
        feedback_parts.append("Subject count unchanged")

    # Criterion 7: VLM visual verification (20 points)
    query_vlm_func = env_info.get('query_vlm')
    vlm_score = 0
    temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        copy_from_env("/tmp/task_end_screenshot.png", temp_screenshot.name)
        vlm_result = _verify_with_vlm(temp_screenshot.name, query_vlm_func)

        if vlm_result.get("success"):
            if vlm_result.get("success_message_visible") or vlm_result.get("subject_list_or_details_visible"):
                vlm_score += 10
            if vlm_result.get("subject_id_visible"):
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

    # Criterion 8: GUI interaction via audit log (30 points penalty if missing)
    audit_count = _safe_int(result.get('audit_log_count', 0))
    audit_baseline = _safe_int(result.get('audit_baseline_count', 0))
    audit_entity_count = _safe_int(result.get('audit_entity_count', 0))
    audit_delta = audit_count - audit_baseline

    gui_verified = audit_delta > 0 and audit_entity_count > 0
    if gui_verified:
        feedback_parts.append(f"GUI audit log: {audit_delta} new entries, {audit_entity_count} subject-specific (GUI confirmed)")
    elif audit_delta > 0:
        gui_verified = True
        feedback_parts.append(f"GUI audit log: {audit_delta} new entries but 0 subject-specific (weak GUI evidence)")
    else:
        score = max(0, score - 30)
        feedback_parts.append("PENALTY (-30): No new audit log entries since setup — possible direct SQL bypass")

    label_acceptable = label.lower() == expected_label.lower()
    passed = score >= 60 and subject_found and label_acceptable and gui_verified

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
