#!/usr/bin/env python3
"""Verifier for create_study_event task."""

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
2. Is there a success message or confirmation that a study event definition was created?
3. Can you see an event named 'Screening Visit' in any list or confirmation?
4. Does the page show an event definitions list, event details, or a "created successfully" message?

Respond in JSON format:
{
    "openclinica_visible": true/false,
    "success_message_visible": true/false,
    "event_name_visible": true/false,
    "event_list_or_details_visible": true/false,
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
        "event_name_visible": parsed.get("event_name_visible", False),
        "event_list_or_details_visible": parsed.get("event_list_or_details_visible", False),
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


def verify_create_study_event(traj, env_info, task_info):
    """Verify that a study event definition was created in OpenClinica."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', 'Screening Visit')
    expected_type = metadata.get('expected_type', 'scheduled')
    expected_repeating = metadata.get('expected_repeating', False)

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_study_event_result.json", temp_file.name)
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

    initial_count = _safe_int(result.get('initial_event_def_count', 0))
    current_count = _safe_int(result.get('current_event_def_count', 0))
    event_found = result.get('event_found', False)
    event = result.get('event', {})

    # Criterion 1: Event exists (15 points)
    if event_found:
        score += 15
        feedback_parts.append("Event definition found")
    else:
        feedback_parts.append("FAIL: Event definition NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Name matches (20 points)
    name = event.get('name', '').strip()
    if name.lower() == expected_name.lower():
        score += 20
        feedback_parts.append(f"Event name correct: {name}")
    elif 'screening' in name.lower() and 'visit' in name.lower():
        score += 8
        feedback_parts.append(f"Event name partially matches: '{name}'")
    elif 'screening' in name.lower():
        score += 5
        feedback_parts.append(f"Event name contains keyword only: '{name}'")
    elif name:
        score += 2
        feedback_parts.append(f"Event name set but different: '{name}'")
    else:
        feedback_parts.append("FAIL: Event name not set")

    # Criterion 3: Type is scheduled (15 points)
    event_type = event.get('type', '').strip().lower()
    if event_type == expected_type:
        score += 15
        feedback_parts.append(f"Event type correct: {event_type}")
    elif event_type:
        score += 2
        feedback_parts.append(f"Event type set but different: '{event_type}'")
    else:
        feedback_parts.append("FAIL: Event type not set")

    # Criterion 4: Repeating flag correct (10 points)
    repeating_raw = str(event.get('repeating', '')).strip().lower()
    is_non_repeating = repeating_raw in ('f', 'false', 'no', '0')
    is_repeating = repeating_raw in ('t', 'true', 'yes', '1')
    if not expected_repeating and is_non_repeating:
        score += 10
        feedback_parts.append(f"Repeating flag correct: non-repeating ({repeating_raw})")
    elif expected_repeating and is_repeating:
        score += 10
        feedback_parts.append(f"Repeating flag correct: repeating ({repeating_raw})")
    elif repeating_raw == '':
        feedback_parts.append("Repeating flag not set (missing data)")
    else:
        feedback_parts.append(f"Repeating flag mismatch: expected {'repeating' if expected_repeating else 'non-repeating'}, got '{repeating_raw}'")

    # Criterion 5: Has description (5 points)
    desc = event.get('description', '').strip()
    if len(desc) >= 10:
        score += 5
        feedback_parts.append(f"Description provided ({len(desc)} chars)")
    elif desc:
        score += 2
        feedback_parts.append(f"Description too short ({len(desc)} chars)")
    else:
        feedback_parts.append("No description set")

    # Criterion 6: Created in correct study (10 points)
    correct_study = result.get('correct_study', False)
    if correct_study:
        score += 10
        feedback_parts.append("Event created in correct study (Phase II Diabetes Trial)")
    elif current_count > initial_count:
        score += 2
        feedback_parts.append("Event count increased but created in wrong study")
    else:
        feedback_parts.append("Event count unchanged or wrong study")

    # Criterion 7: VLM visual verification (20 points)
    query_vlm_func = env_info.get('query_vlm')
    vlm_score = 0
    temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        copy_from_env("/tmp/task_end_screenshot.png", temp_screenshot.name)
        vlm_result = _verify_with_vlm(temp_screenshot.name, query_vlm_func)

        if vlm_result.get("success"):
            if vlm_result.get("success_message_visible") or vlm_result.get("event_list_or_details_visible"):
                vlm_score += 10
            if vlm_result.get("event_name_visible"):
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

    # Criterion 8: GUI interaction via audit log (25 points penalty if missing)
    audit_count = _safe_int(result.get('audit_log_count', 0))
    audit_baseline = _safe_int(result.get('audit_baseline_count', 0))
    audit_entity_count = _safe_int(result.get('audit_entity_count', 0))
    audit_delta = audit_count - audit_baseline

    gui_verified = audit_delta > 0 and audit_entity_count > 0
    if gui_verified:
        feedback_parts.append(f"GUI audit log: {audit_delta} new entries, {audit_entity_count} event-specific (GUI confirmed)")
    elif audit_delta > 0:
        gui_verified = True
        feedback_parts.append(f"GUI audit log: {audit_delta} new entries but 0 event-specific (weak GUI evidence)")
    else:
        score = max(0, score - 25)
        feedback_parts.append("PENALTY (-25): No new audit log entries since setup — possible direct SQL bypass")

    name_acceptable = name.lower() == expected_name.lower() or ('screening' in name.lower() and 'visit' in name.lower())
    passed = score >= 60 and event_found and name_acceptable and gui_verified

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
