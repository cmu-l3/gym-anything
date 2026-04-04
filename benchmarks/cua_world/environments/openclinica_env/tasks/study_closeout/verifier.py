#!/usr/bin/env python3
"""Verifier for study_closeout task."""

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


def verify_study_closeout(traj, env_info, task_info):
    """
    Verify study_closeout task completion.

    Scoring (100 points total):
    - Criterion 1: "End of Study Assessment" event def added to DM Trial  -> 20 pts
    - Criterion 2: DM-103 status_id != 1 (discontinued/withdrawn)         -> 20 pts
    - Criterion 3: DM Trial status_id != 1 (no longer Available)          -> 20 pts
    - Criterion 4: AP Pilot status_id is 5 or 6 (Frozen or Locked)        -> 20 pts
    - Criterion 5: Export file exists in Desktop or Downloads              -> 20 pts
    - VLM visual check: up to 10 pts bonus
    - Audit log penalty: -20 if no GUI interaction detected

    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # --- Load result file ---
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/study_closeout_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script did not run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # --- Verify integrity nonce ---
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
            "feedback": "INTEGRITY FAIL: Result file nonce mismatch — possible tampering"
        }

    score = 0
    feedback_parts = []

    # --- Criterion 1: "End of Study Assessment" event definition exists in DM Trial (20 pts) ---
    # Accept broad name match: contains ("end" + "assess") OR ("end" + "study") OR ("final" + "assess")
    eos_exists = result.get('eos_event_def_exists', False)
    eos_name = result.get('eos_event_def_name', '').lower()
    eos_type = result.get('eos_event_def_type', '')
    eos_repeating = str(result.get('eos_event_def_repeating', 'true')).lower()

    # Double-check name match in verifier (export script uses DB LIKE, but verify here too)
    name_matches = (
        ('end' in eos_name and 'assess' in eos_name) or
        ('end' in eos_name and 'study' in eos_name) or
        ('final' in eos_name and 'assess' in eos_name)
    )

    if eos_exists and name_matches:
        score += 20
        feedback_parts.append(f"End of Study Assessment event def added (+20): name='{result.get('eos_event_def_name', '')}'")
        # Report event type and repeating as informational (no bonus points)
        if eos_type.lower() == 'unscheduled':
            feedback_parts.append(f"Event type correct: Unscheduled")
        else:
            feedback_parts.append(f"Event type: '{eos_type}' (expected Unscheduled — informational)")
        if eos_repeating in ('false', 'f', '0', 'no'):
            feedback_parts.append("Event repeating: non-repeating (correct)")
        else:
            feedback_parts.append(f"Event repeating: '{eos_repeating}' (expected non-repeating — informational)")
    elif eos_exists and not name_matches:
        feedback_parts.append(
            f"PARTIAL: Event def found but name '{result.get('eos_event_def_name', '')}' "
            f"does not match expected pattern (0/20)"
        )
    else:
        feedback_parts.append("FAIL: 'End of Study Assessment' event definition not found in DM Trial (0/20)")

    # --- Criterion 2: DM-103 status_id != 1 (discontinued/withdrawn) (20 pts) ---
    dm103_status = _safe_int(result.get('dm103_status_id', 1), default=1)
    dm103_baseline = _safe_int(result.get('baseline_dm103_status', 1), default=1)

    if dm103_status != 1:
        score += 20
        status_label = {2: 'completed', 3: 'discontinued', 4: 'removed'}.get(dm103_status, str(dm103_status))
        feedback_parts.append(f"DM-103 discontinuation/withdrawal confirmed (+20): status_id={dm103_status} ({status_label})")
    else:
        feedback_parts.append(
            f"FAIL: DM-103 still Active (status_id=1) — "
            f"expected discontinuation/withdrawal (0/20)"
        )

    # --- Criterion 3: DM Trial status_id != 1 (no longer Available) (20 pts) ---
    # Accept status 4 (Completed), 5 (Frozen), or 6 (Locked)
    dm_trial_status = _safe_int(result.get('dm_trial_status_id', 1), default=1)
    dm_status_label = {
        1: 'Available', 2: 'Design', 4: 'Completed', 5: 'Frozen', 6: 'Locked'
    }.get(dm_trial_status, str(dm_trial_status))

    if dm_trial_status != 1:
        score += 20
        feedback_parts.append(f"DM Trial status changed from Available (+20): now {dm_status_label} (status_id={dm_trial_status})")
        if dm_trial_status == 5:
            feedback_parts.append("DM Trial set to Frozen — matches recommended target status")
        elif dm_trial_status == 6:
            feedback_parts.append("DM Trial set to Locked — stricter than recommended but accepted")
        elif dm_trial_status == 4:
            feedback_parts.append("DM Trial set to Completed — accepted (task description recommended Frozen)")
    else:
        feedback_parts.append(
            "FAIL: DM Trial status is still Available (status_id=1) — "
            "expected Frozen (5), Locked (6), or Completed (4) (0/20)"
        )

    # --- Criterion 4: AP Pilot status_id is 5 or 6 (Frozen or Locked) (20 pts) ---
    # Starting status was 4 (Completed). Must have moved to 5 (Frozen) or 6 (Locked).
    ap_pilot_status = _safe_int(result.get('ap_pilot_status_id', 4), default=4)
    ap_status_label = {
        1: 'Available', 2: 'Design', 4: 'Completed', 5: 'Frozen', 6: 'Locked'
    }.get(ap_pilot_status, str(ap_pilot_status))

    if ap_pilot_status in (5, 6):
        score += 20
        feedback_parts.append(f"AP Pilot locked/frozen (+20): status_id={ap_pilot_status} ({ap_status_label})")
        if ap_pilot_status == 6:
            feedback_parts.append("AP Pilot set to Locked — matches task requirement")
        else:
            feedback_parts.append("AP Pilot set to Frozen — partially accepted (task asked for Locked)")
    elif ap_pilot_status == 4:
        feedback_parts.append(
            "FAIL: AP Pilot status unchanged (still Completed, status_id=4) — "
            "expected Locked (6) or Frozen (5) (0/20)"
        )
    elif ap_pilot_status == 1:
        feedback_parts.append(
            "FAIL: AP Pilot reverted to Available (status_id=1) — "
            "expected Locked (6) or Frozen (5) (0/20)"
        )
    else:
        feedback_parts.append(
            f"FAIL: AP Pilot in unexpected state {ap_status_label} (status_id={ap_pilot_status}) — "
            f"expected Locked (6) or Frozen (5) (0/20)"
        )

    # --- Criterion 5: Export file exists in Desktop or Downloads (20 pts) ---
    export_exists = result.get('export_file_exists', False)
    export_path = result.get('export_file_path', '')

    if export_exists:
        score += 20
        feedback_parts.append(f"Export file found (+20): {export_path}")
    else:
        feedback_parts.append(
            "FAIL: No export file found in /home/ga/Desktop or /home/ga/Downloads — "
            "export was not performed or saved elsewhere (0/20)"
        )

    # --- VLM visual check (up to 10 pts bonus) ---
    query_vlm_func = env_info.get('query_vlm')
    vlm_score = 0
    temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        copy_from_env("/tmp/task_end_screenshot.png", temp_screenshot.name)
        if query_vlm_func and os.path.exists(temp_screenshot.name):
            vlm_result = query_vlm_func(
                prompt=(
                    "Look at this OpenClinica screenshot. "
                    "Is OpenClinica visible? "
                    "Does the screenshot show study administration, study status settings, "
                    "subject management, event definition management, or data export? "
                    "Answer in JSON: {"
                    "\"openclinica_visible\": true/false, "
                    "\"admin_or_closeout_activity\": true/false, "
                    "\"export_or_extract_visible\": true/false"
                    "}"
                ),
                image=temp_screenshot.name
            )
            parsed = vlm_result.get("parsed", {}) if vlm_result.get("success") else {}
            if parsed.get("openclinica_visible"):
                vlm_score += 4
            if parsed.get("admin_or_closeout_activity"):
                vlm_score += 4
            if parsed.get("export_or_extract_visible"):
                vlm_score += 2
            feedback_parts.append(f"VLM visual check: {vlm_score}/10")
    except Exception as e:
        feedback_parts.append(f"VLM check skipped: {e}")
    finally:
        if os.path.exists(temp_screenshot.name):
            os.unlink(temp_screenshot.name)
    score += vlm_score

    # --- Audit log penalty: -20 if no GUI interaction detected ---
    audit_count = _safe_int(result.get('audit_log_count', 0))
    audit_baseline = _safe_int(result.get('audit_baseline_count', 0))
    audit_delta = audit_count - audit_baseline

    if audit_delta > 0:
        feedback_parts.append(f"GUI audit log: {audit_delta} new entries (GUI interaction confirmed)")
    else:
        score = max(0, score - 20)
        feedback_parts.append(
            "PENALTY (-20): No audit log entries detected — possible direct DB bypass instead of GUI use"
        )

    passed = score >= 70

    return {
        "passed": passed,
        "score": min(score, 110),  # cap at 110 to allow VLM bonus over 100
        "feedback": " | ".join(feedback_parts),
    }
