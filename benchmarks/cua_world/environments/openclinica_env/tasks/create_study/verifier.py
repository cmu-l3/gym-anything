#!/usr/bin/env python3
"""Verifier for create_study task."""

import json
import tempfile
import os
import logging
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from vlm_utils import query_vlm as _query_vlm_direct

logger = logging.getLogger(__name__)


def _build_vlm_prompt():
    """Build VLM prompt to verify study creation is visible in OpenClinica."""
    return """Examine this screenshot of OpenClinica (a clinical trial management system).

Check the following:
1. Is OpenClinica visible in Firefox (not an error page, login page, or blank page)?
2. Is there a success message or confirmation that a study was created?
3. Can you see a study named 'Hypertension Management Trial' or similar in any list or confirmation?
4. Does the page show a study list, study details, or a "study created" confirmation?

Respond in JSON format:
{
    "openclinica_visible": true/false,
    "success_message_visible": true/false,
    "study_name_visible": true/false,
    "study_list_or_details_visible": true/false,
    "page_description": "brief description of what you see",
    "confidence": "low"/"medium"/"high"
}
"""


def _verify_with_vlm(screenshot_path, query_vlm_func):
    """Run VLM verification on the final screenshot."""
    if not query_vlm_func:
        return {"success": False, "error": "VLM not available"}

    if not os.path.exists(screenshot_path):
        return {"success": False, "error": f"Screenshot not found: {screenshot_path}"}

    prompt = _build_vlm_prompt()
    vlm_result = query_vlm_func(prompt=prompt, image=screenshot_path)

    if not vlm_result.get("success"):
        return {"success": False, "error": vlm_result.get("error", "VLM query failed")}

    parsed = vlm_result.get("parsed", {})
    return {
        "success": True,
        "openclinica_visible": parsed.get("openclinica_visible", False),
        "success_message_visible": parsed.get("success_message_visible", False),
        "study_name_visible": parsed.get("study_name_visible", False),
        "study_list_or_details_visible": parsed.get("study_list_or_details_visible", False),
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


def verify_create_study(traj, env_info, task_info):
    """Verify that a clinical study was created in OpenClinica."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', 'Hypertension Management Trial')
    expected_protocol = metadata.get('expected_protocol_id', 'HMT-2024-001')
    expected_pi = metadata.get('expected_pi', 'Dr. James Wilson')
    min_summary_length = metadata.get('min_summary_length', 50)
    required_keywords = metadata.get('required_summary_keywords', ['hypertension', 'blood pressure'])

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_study_result.json", temp_file.name)
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

    initial_count = _safe_int(result.get('initial_study_count', 0))
    current_count = _safe_int(result.get('current_study_count', 0))
    study_found = result.get('study_found', False)
    study = result.get('study', {})

    # Criterion 1: Study exists (15 points)
    if study_found:
        score += 15
        feedback_parts.append("Study found in database")
    else:
        feedback_parts.append("FAIL: Study NOT found in database")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Name matches (20 points)
    name = study.get('name', '').strip()
    name_lower = name.lower()
    expected_lower = expected_name.lower()

    if name_lower == expected_lower:
        score += 20
        feedback_parts.append(f"Study name correct: {name}")
    elif 'hypertension' in name_lower and 'management' in name_lower:
        score += 8
        feedback_parts.append(f"Study name partially matches: '{name}'")
    elif 'hypertension' in name_lower:
        score += 5
        feedback_parts.append(f"Study name contains keyword only: '{name}'")
    else:
        feedback_parts.append(f"FAIL: Name mismatch: expected '{expected_name}', got '{name}'")

    # Criterion 3: Protocol ID matches (15 points)
    protocol = study.get('protocol_id', '').strip()
    if protocol.lower() == expected_protocol.lower():
        score += 15
        feedback_parts.append(f"Protocol ID correct: {protocol}")
    elif protocol:
        score += 3
        feedback_parts.append(f"Protocol ID set but wrong: expected '{expected_protocol}', got '{protocol}'")
    else:
        feedback_parts.append("FAIL: Protocol ID not set")

    # Criterion 4: Protocol type is Interventional (5 points)
    protocol_type = study.get('protocol_type', '').strip().lower()
    if protocol_type == 'interventional':
        score += 5
        feedback_parts.append(f"Protocol type correct: {protocol_type}")
    elif protocol_type:
        score += 2
        feedback_parts.append(f"Protocol type set: '{protocol_type}' (expected 'interventional')")
    else:
        feedback_parts.append("Protocol type not set")

    # Criterion 5: Principal Investigator (10 points)
    pi = study.get('principal_investigator', '').strip()
    if pi.lower() == expected_pi.lower():
        score += 10
        feedback_parts.append(f"PI correct: {pi}")
    elif 'wilson' in pi.lower():
        score += 4
        feedback_parts.append(f"PI partially matches: '{pi}'")
    elif pi:
        score += 1
        feedback_parts.append(f"PI set but different: '{pi}'")
    else:
        feedback_parts.append("FAIL: PI not set")

    # Criterion 6: Summary with keywords (10 points)
    summary = study.get('summary', '')
    summary_length = study.get('summary_length', len(summary))
    summary_lower = summary.lower()

    keywords_found = [kw for kw in required_keywords if kw.lower() in summary_lower]
    keywords_missing = [kw for kw in required_keywords if kw.lower() not in summary_lower]

    if summary_length >= min_summary_length and len(keywords_missing) == 0:
        score += 10
        feedback_parts.append(f"Summary valid: {summary_length} chars with all keywords")
    elif summary_length >= min_summary_length:
        score += 4
        feedback_parts.append(f"Summary length OK ({summary_length} chars) but missing keywords: {keywords_missing}")
    elif summary_length > 0:
        score += 1
        feedback_parts.append(f"Summary too short: {summary_length} chars")
    else:
        feedback_parts.append("FAIL: No summary provided")

    # Criterion 7: Study was newly created (10 points)
    newly_created = current_count > initial_count
    if newly_created:
        score += 10
        feedback_parts.append("Study count increased (newly created)")
    else:
        feedback_parts.append("Study count unchanged (may have existed before)")

    # Criterion 8: VLM visual verification (15 points)
    query_vlm_func = env_info.get('query_vlm')
    vlm_score = 0
    temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        copy_from_env("/tmp/task_end_screenshot.png", temp_screenshot.name)
        vlm_result = _verify_with_vlm(temp_screenshot.name, query_vlm_func)

        if vlm_result.get("success"):
            if vlm_result.get("success_message_visible") or vlm_result.get("study_list_or_details_visible"):
                vlm_score += 8
            if vlm_result.get("study_name_visible"):
                vlm_score += 7
            feedback_parts.append(f"VLM visual check: {vlm_score}/15 (confidence: {vlm_result.get('confidence', 'n/a')})")
        else:
            vlm_score = 0
            feedback_parts.append(f"VLM unavailable: {vlm_score}/15")
    except Exception as e:
        vlm_score = 0
        feedback_parts.append(f"VLM check failed ({e}): {vlm_score}/15")
    finally:
        if os.path.exists(temp_screenshot.name):
            os.unlink(temp_screenshot.name)

    score += vlm_score

    # Criterion 9: GUI interaction verification via audit log (25 points penalty if missing)
    # Two-layer check: (a) generic audit delta, (b) entity-specific audit entries
    audit_count = _safe_int(result.get('audit_log_count', 0))
    audit_baseline = _safe_int(result.get('audit_baseline_count', 0))
    audit_entity_count = _safe_int(result.get('audit_entity_count', 0))
    audit_delta = audit_count - audit_baseline

    # GUI verified if both generic delta > 0 AND entity-specific entries exist
    gui_verified = audit_delta > 0 and audit_entity_count > 0
    if gui_verified:
        feedback_parts.append(f"GUI audit log: {audit_delta} new entries, {audit_entity_count} study-specific (GUI confirmed)")
    elif audit_delta > 0:
        # Generic entries exist but no study-specific ones — weaker evidence
        gui_verified = True  # Still pass but note the concern
        feedback_parts.append(f"GUI audit log: {audit_delta} new entries but 0 study-specific (weak GUI evidence)")
    else:
        score = max(0, score - 25)
        feedback_parts.append("PENALTY (-25): No new audit log entries since setup — possible direct SQL bypass")

    # Pass criteria: require name match AND GUI interaction evidence
    name_acceptable = name_lower == expected_lower or ('hypertension' in name_lower and 'management' in name_lower)
    passed = score >= 65 and study_found and name_acceptable and gui_verified

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
