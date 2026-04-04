#!/usr/bin/env python3
"""Verifier for crf_assignment_and_entry task."""

import json
import tempfile
import os
import logging
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from vlm_utils import query_vlm as _query_vlm_direct

logger = logging.getLogger(__name__)


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


def _build_vlm_prompt():
    return """Examine this screenshot of OpenClinica (a clinical trial management system).

Check the following:
1. Is OpenClinica visible in Firefox (not an error page, login page, or blank page)?
2. Can you see any CRF data entry form, subject event schedule, or CRF assignment page?
3. Is there evidence of data entry fields (blood pressure, heart rate) or a completed CRF?
4. Can you see a subject record (DM-102), event schedule, or event CRF?

Respond in JSON format:
{
    "openclinica_visible": true/false,
    "crf_or_data_entry_visible": true/false,
    "subject_or_event_visible": true/false,
    "completion_or_success_visible": true/false,
    "confidence": "low"/"medium"/"high"
}
"""


def verify_crf_assignment_and_entry(traj, env_info, task_info):
    """
    Verify crf_assignment_and_entry task completion.

    Scoring (100 points + bonuses):
    - Criterion 1: Vital Signs CRF exists in DB (name='Vital Signs'): 20 pts
    - Criterion 2: CRF assigned to Baseline Assessment event def: 20 pts
    - Criterion 3: CRF assigned to Follow-up Visit event def: 15 pts
    - Criterion 4: DM-102 Baseline Assessment event exists: 20 pts
        + 5 bonus if date is 2024-02-05
    - Criterion 5: event_crf exists (data entry started): 15 pts
    - Criterion 6: item_data count > 0: 5 pts
        + 5 bonus if values 135 or 88 found
    - VLM visual check: up to 10 pts
    - Audit log penalty: -20 if no GUI interaction detected

    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/crf_assignment_and_entry_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script did not run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Verify integrity nonce
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

    # ------------------------------------------------------------------
    # Criterion 1: Vital Signs CRF exists in DB (20 pts)
    # ------------------------------------------------------------------
    crf_exists = result.get('crf_exists', False)
    crf_name = result.get('crf_name', '').strip()
    if crf_exists:
        score += 20
        feedback_parts.append(f"Vital Signs CRF found in database: '{crf_name}' (+20)")
    else:
        feedback_parts.append("FAIL: Vital Signs CRF NOT found in database (0/20)")

    # ------------------------------------------------------------------
    # Criterion 2: CRF assigned to Baseline Assessment (20 pts)
    # ------------------------------------------------------------------
    if result.get('crf_assigned_to_baseline', False):
        score += 20
        feedback_parts.append("Vital Signs CRF assigned to Baseline Assessment (+20)")
    else:
        feedback_parts.append("FAIL: Vital Signs CRF NOT assigned to Baseline Assessment (0/20)")

    # ------------------------------------------------------------------
    # Criterion 3: CRF assigned to Follow-up Visit (15 pts)
    # ------------------------------------------------------------------
    if result.get('crf_assigned_to_followup', False):
        score += 15
        feedback_parts.append("Vital Signs CRF assigned to Follow-up Visit (+15)")
    else:
        feedback_parts.append("FAIL: Vital Signs CRF NOT assigned to Follow-up Visit (0/15)")

    # ------------------------------------------------------------------
    # Criterion 4: DM-102 Baseline Assessment event exists (20 pts + 5 bonus)
    # ------------------------------------------------------------------
    dm102_event_exists = result.get('dm102_baseline_event_exists', False)
    if dm102_event_exists:
        score += 20
        feedback_parts.append("DM-102 Baseline Assessment event scheduled (+20)")
        if result.get('dm102_baseline_event_date_correct', False):
            score += 5
            feedback_parts.append("DM-102 event date correct: 2024-02-05 (+5 bonus)")
        else:
            event_date = result.get('dm102_baseline_event_date', 'unknown')
            feedback_parts.append(f"DM-102 event date: '{event_date}' (expected 2024-02-05, no bonus)")
    else:
        feedback_parts.append("FAIL: DM-102 Baseline Assessment event NOT found (0/20)")

    # ------------------------------------------------------------------
    # Criterion 5: event_crf exists — data entry started (15 pts)
    # ------------------------------------------------------------------
    event_crf_exists = result.get('event_crf_exists', False)
    if event_crf_exists:
        score += 15
        feedback_parts.append("Data entry (event_crf) found for DM-102 Baseline Assessment (+15)")
    else:
        feedback_parts.append("FAIL: No event_crf (data entry) found for DM-102 Baseline Assessment (0/15)")

    # ------------------------------------------------------------------
    # Criterion 6: item_data rows present (5 pts + 5 bonus for values)
    # ------------------------------------------------------------------
    item_data_count = _safe_int(result.get('item_data_count', 0))
    if item_data_count > 0:
        score += 5
        feedback_parts.append(f"item_data rows found: {item_data_count} (+5)")
        # Bonus: expected values present
        has_systolic = result.get('has_systolic_value', False)
        has_diastolic = result.get('has_diastolic_value', False)
        has_heart_rate = result.get('has_heart_rate_value', False)
        if has_systolic or has_diastolic:
            score += 5
            found_vals = []
            if has_systolic:
                found_vals.append("135 (systolic BP)")
            if has_diastolic:
                found_vals.append("88 (diastolic BP)")
            if has_heart_rate:
                found_vals.append("78 (heart rate)")
            feedback_parts.append(f"Expected values found in item_data: {', '.join(found_vals)} (+5 bonus)")
        else:
            feedback_parts.append("Expected values (135/88/78) NOT found in item_data (no bonus)")
    else:
        feedback_parts.append("FAIL: No item_data rows found (0/5)")

    # ------------------------------------------------------------------
    # VLM visual check (up to 10 pts)
    # ------------------------------------------------------------------
    query_vlm_func = env_info.get('query_vlm')
    vlm_score = 0
    temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        copy_from_env("/tmp/task_end_screenshot.png", temp_screenshot.name)
        if query_vlm_func and os.path.exists(temp_screenshot.name):
            vlm_result = query_vlm_func(
                prompt=_build_vlm_prompt(),
                image=temp_screenshot.name,
            )
            parsed = vlm_result.get("parsed", {}) if vlm_result.get("success") else {}
            if parsed.get("openclinica_visible"):
                vlm_score += 3
            if parsed.get("crf_or_data_entry_visible") or parsed.get("subject_or_event_visible"):
                vlm_score += 4
            if parsed.get("completion_or_success_visible"):
                vlm_score += 3
            feedback_parts.append(
                f"VLM visual check: {vlm_score}/10 (confidence: {parsed.get('confidence', 'n/a')})"
            )
        else:
            feedback_parts.append("VLM visual check: skipped (VLM not available)")
    except Exception as e:
        feedback_parts.append(f"VLM check failed ({e}): 0/10")
    finally:
        if os.path.exists(temp_screenshot.name):
            os.unlink(temp_screenshot.name)
    score += vlm_score

    # ------------------------------------------------------------------
    # Audit log check — penalty if no GUI interaction detected
    # ------------------------------------------------------------------
    audit_count = _safe_int(result.get('audit_log_count', 0))
    audit_baseline = _safe_int(result.get('audit_baseline_count', 0))
    audit_delta = audit_count - audit_baseline
    if audit_delta > 0:
        feedback_parts.append(f"GUI audit log: {audit_delta} new entries (GUI interaction confirmed)")
    else:
        score = max(0, score - 20)
        feedback_parts.append("PENALTY (-20): No audit log entries since setup — possible direct DB bypass")

    passed = score >= 70

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
    }
