#!/usr/bin/env python3
"""Verifier for create_crf task."""

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
2. Is there a success message or confirmation that a CRF (Case Report Form) was created?
3. Can you see a CRF named 'Vital Signs' in any list or confirmation?
4. Does the page show a CRF list, CRF details, or a "CRF created" confirmation?

Respond in JSON format:
{
    "openclinica_visible": true/false,
    "success_message_visible": true/false,
    "crf_name_visible": true/false,
    "crf_list_or_details_visible": true/false,
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
        "crf_name_visible": parsed.get("crf_name_visible", False),
        "crf_list_or_details_visible": parsed.get("crf_list_or_details_visible", False),
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


def verify_create_crf(traj, env_info, task_info):
    """Verify that a CRF was created in OpenClinica."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_crf_name', 'Vital Signs')
    expected_min_items = metadata.get('expected_min_items', 5)

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_crf_result.json", temp_file.name)
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

    initial_count = _safe_int(result.get('initial_crf_count', 0))
    current_count = _safe_int(result.get('current_crf_count', 0))
    crf_found = result.get('crf_found', False)
    crf = result.get('crf', {})

    # Criterion 1: CRF exists (15 points)
    if crf_found:
        score += 15
        feedback_parts.append("CRF found in database")
    else:
        feedback_parts.append("FAIL: CRF NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Name matches (20 points)
    name = crf.get('name', '').strip()
    if name.lower() == expected_name.lower():
        score += 20
        feedback_parts.append(f"CRF name correct: {name}")
    elif 'vital' in name.lower() and 'sign' in name.lower():
        score += 8
        feedback_parts.append(f"CRF name partially matches: '{name}'")
    elif 'vital' in name.lower():
        score += 5
        feedback_parts.append(f"CRF name contains keyword only: '{name}'")
    elif name:
        score += 2
        feedback_parts.append(f"CRF name set but different: '{name}'")
    else:
        feedback_parts.append("FAIL: CRF name not set")

    # Criterion 3: Has a version (10 points)
    version = crf.get('version', '').strip()
    if version:
        score += 10
        feedback_parts.append(f"CRF version created: {version}")
    else:
        feedback_parts.append("No CRF version found")

    # Criterion 4: Has expected number of items (15 points)
    item_count = _safe_int(crf.get('item_count', 0))
    if item_count >= expected_min_items:
        score += 15
        feedback_parts.append(f"CRF has {item_count} items (>= {expected_min_items} expected)")
    elif item_count > 0:
        score += 5
        feedback_parts.append(f"CRF has {item_count} items (expected >= {expected_min_items})")
    else:
        feedback_parts.append(f"No CRF items found (expected >= {expected_min_items})")

    # Criterion 5: Newly created (10 points)
    if current_count > initial_count:
        score += 10
        feedback_parts.append("CRF count increased")
    else:
        feedback_parts.append("CRF count unchanged")

    # Criterion 6: VLM visual verification (20 points)
    query_vlm_func = env_info.get('query_vlm')
    vlm_score = 0
    temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        copy_from_env("/tmp/task_end_screenshot.png", temp_screenshot.name)
        vlm_result = _verify_with_vlm(temp_screenshot.name, query_vlm_func)

        if vlm_result.get("success"):
            if vlm_result.get("success_message_visible") or vlm_result.get("crf_list_or_details_visible"):
                vlm_score += 10
            if vlm_result.get("crf_name_visible"):
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

    # Criterion 7: GUI interaction via audit log (25 points penalty if missing)
    audit_count = _safe_int(result.get('audit_log_count', 0))
    audit_baseline = _safe_int(result.get('audit_baseline_count', 0))
    audit_entity_count = _safe_int(result.get('audit_entity_count', 0))
    audit_delta = audit_count - audit_baseline

    gui_verified = audit_delta > 0 and audit_entity_count > 0
    if gui_verified:
        feedback_parts.append(f"GUI audit log: {audit_delta} new entries, {audit_entity_count} CRF-specific (GUI confirmed)")
    elif audit_delta > 0:
        gui_verified = True
        feedback_parts.append(f"GUI audit log: {audit_delta} new entries but 0 CRF-specific (weak GUI evidence)")
    else:
        score = max(0, score - 25)
        feedback_parts.append("PENALTY (-25): No new audit log entries since setup — possible direct SQL bypass")

    name_acceptable = name.lower() == expected_name.lower() or ('vital' in name.lower() and 'sign' in name.lower())
    passed = score >= 60 and crf_found and name_acceptable and gui_verified

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
