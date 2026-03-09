#!/usr/bin/env python3
"""Verifier for schedule_and_track_visits task."""

import json
import tempfile
import os
import logging
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from vlm_utils import query_vlm as _query_vlm_direct

logger = logging.getLogger(__name__)


def _safe_int(value, default=0):
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        try:
            return int(value.strip())
        except (ValueError, AttributeError):
            return default
    return default


def verify_schedule_and_track_visits(traj, env_info, task_info):
    """
    Verify schedule_and_track_visits task completion.

    Scoring (100 points):
    - DM-101 Baseline Assessment event exists: 20 pts (+ 5 bonus for correct date)
    - DM-102 Week 4 Follow-up event exists: 20 pts (+ 5 bonus for correct date)
    - DM-104 enrolled as study subject: 25 pts
    - DM-104 Baseline Assessment event scheduled: 20 pts (+ 5 bonus for correct date)
    - VLM visual check: up to 15 pts
    - Audit log penalty: -25 if no GUI interaction detected

    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/schedule_and_track_visits_result.json", temp_file.name)
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
        return {"passed": False, "score": 0,
                "feedback": "INTEGRITY FAIL: Result file nonce mismatch — possible tampering"}

    score = 0
    feedback_parts = []

    # Criterion 1: DM-101 Baseline Assessment event (20 pts + 5 bonus)
    if result.get('dm101_event_found'):
        score += 20
        feedback_parts.append("DM-101 Baseline Assessment scheduled (+20)")
        if result.get('dm101_event_date_correct'):
            score += 5
            feedback_parts.append("DM-101 event date correct 2024-01-15 (+5)")
        else:
            feedback_parts.append(f"DM-101 event date: {result.get('dm101_event_date', 'unknown')} (expected 2024-01-15)")
    else:
        feedback_parts.append("FAIL: DM-101 Baseline Assessment not scheduled (0/20)")

    # Criterion 2: DM-102 Week 4 Follow-up event (20 pts + 5 bonus)
    if result.get('dm102_event_found'):
        score += 20
        feedback_parts.append("DM-102 Week 4 Follow-up scheduled (+20)")
        if result.get('dm102_event_date_correct'):
            score += 5
            feedback_parts.append("DM-102 event date correct 2024-03-01 (+5)")
        else:
            feedback_parts.append(f"DM-102 event date: {result.get('dm102_event_date', 'unknown')} (expected 2024-03-01)")
    else:
        feedback_parts.append("FAIL: DM-102 Week 4 Follow-up not scheduled (0/20)")

    # Criterion 3: DM-104 enrolled (25 pts)
    if result.get('dm104_enrolled'):
        score += 25
        feedback_parts.append("DM-104 enrolled as new subject (+25)")
        gender = result.get('dm104_gender', '').strip().lower()
        dob = result.get('dm104_dob', '').strip()
        if gender in ('m', 'male'):
            feedback_parts.append(f"DM-104 gender correct: {gender}")
        else:
            feedback_parts.append(f"DM-104 gender: '{gender}' (expected male)")
        if '1978-05-23' in dob or '1978' in dob:
            feedback_parts.append(f"DM-104 DOB correct: {dob}")
        else:
            feedback_parts.append(f"DM-104 DOB: '{dob}' (expected 1978-05-23)")
    else:
        feedback_parts.append("FAIL: DM-104 not enrolled (0/25)")

    # Criterion 4: DM-104 Baseline Assessment event (20 pts + 5 bonus)
    if result.get('dm104_event_found'):
        score += 20
        feedback_parts.append("DM-104 Baseline Assessment scheduled (+20)")
        if result.get('dm104_event_date_correct'):
            score += 5
            feedback_parts.append("DM-104 event date correct 2024-01-22 (+5)")
        else:
            feedback_parts.append(f"DM-104 event date: {result.get('dm104_event_date', 'unknown')} (expected 2024-01-22)")
    else:
        feedback_parts.append("FAIL: DM-104 Baseline Assessment not scheduled (0/20)")

    # Criterion 5: VLM visual verification (up to 15 pts)
    query_vlm_func = env_info.get('query_vlm')
    vlm_score = 0
    temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        copy_from_env("/tmp/task_end_screenshot.png", temp_screenshot.name)
        if query_vlm_func and os.path.exists(temp_screenshot.name):
            vlm_result = query_vlm_func(
                prompt="""Look at this OpenClinica screenshot. Is OpenClinica visible with a subject schedule, event calendar, or a list of scheduled visits? Answer in JSON: {"openclinica_visible": true/false, "schedule_visible": true/false, "subject_visible": true/false}""",
                image=temp_screenshot.name
            )
            parsed = vlm_result.get("parsed", {}) if vlm_result.get("success") else {}
            if parsed.get("openclinica_visible"):
                vlm_score += 5
            if parsed.get("schedule_visible") or parsed.get("subject_visible"):
                vlm_score += 10
            feedback_parts.append(f"VLM visual check: {vlm_score}/15")
    except Exception as e:
        feedback_parts.append(f"VLM check skipped: {e}")
    finally:
        if os.path.exists(temp_screenshot.name):
            os.unlink(temp_screenshot.name)
    score += vlm_score

    # Audit log check — penalty if no GUI interaction
    audit_count = _safe_int(result.get('audit_log_count', 0))
    audit_baseline = _safe_int(result.get('audit_baseline_count', 0))
    audit_delta = audit_count - audit_baseline
    if audit_delta > 0:
        feedback_parts.append(f"GUI audit log: {audit_delta} new entries (GUI interaction confirmed)")
    else:
        score = max(0, score - 25)
        feedback_parts.append("PENALTY (-25): No audit log entries — possible direct DB bypass")

    passed = score >= 70

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
    }
