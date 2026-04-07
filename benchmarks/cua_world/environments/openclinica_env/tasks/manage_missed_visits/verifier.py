#!/usr/bin/env python3
"""Verifier for manage_missed_visits task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _build_vlm_prompt():
    """Build VLM prompt to verify OpenClinica interface shows missed visits or notes."""
    return """Examine this screenshot of OpenClinica (a clinical trial management system).

Check the following details:
1. Is OpenClinica visible in the browser?
2. Does the page show the 'Subject Matrix', 'View Subject' page, or 'Notes & Discrepancies' interface?
3. Are there any visual indicators of a missed/skipped/stopped event (e.g., a grayed-out icon, a red 'X', or a status reading 'skipped'/'stopped')?
4. Is there any discrepancy note or flag visible on the screen?

Respond in JSON format:
{
    "openclinica_visible": true/false,
    "matrix_or_subject_view": true/false,
    "skipped_stopped_indicator": true/false,
    "discrepancy_note_visible": true/false,
    "confidence": "low"/"medium"/"high"
}
"""


def _safe_int(value, default=0):
    try:
        return int(value)
    except (ValueError, TypeError):
        return default


def verify_manage_missed_visits(traj, env_info, task_info):
    """
    Verify the manage_missed_visits task completion.

    Scoring (100 pts total):
      - DM-101 Event Status Skipped/Stopped (5 or 6): 10 pts
      - DM-101 Discrepancy Note ('covid'): 15 pts
      - DM-102 Event Status Skipped/Stopped (5 or 6): 10 pts
      - DM-102 Discrepancy Note ('transportation'): 15 pts
      - DM-103 Event Status Skipped/Stopped (5 or 6): 10 pts
      - DM-103 Discrepancy Note ('withdrew'): 15 pts
      - VLM Visual Check: up to 25 pts
      - Audit Penalty: -30 if no UI interaction

    Pass threshold: 70 points
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load exported result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/manage_missed_visits_result.json", temp_file.name)
        with open(temp_file.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Verify Integrity Nonce
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, "r") as f:
            expected_nonce = f.read().strip()
    except Exception:
        expected_nonce = ""
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    result_nonce = result.get("result_nonce", "")
    if expected_nonce and result_nonce != expected_nonce:
        return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: Result nonce mismatch"}

    score = 0
    feedback_parts = []
    
    valid_statuses = [5, 6]  # 5=Stopped, 6=Skipped

    # 3. Check DM-101
    dm101_status = _safe_int(result.get("dm101_status_id"))
    if dm101_status in valid_statuses:
        score += 10
        feedback_parts.append("DM-101 event status updated successfully (+10)")
    else:
        feedback_parts.append(f"FAIL: DM-101 event status is {dm101_status} (expected 5 or 6)")

    if _safe_int(result.get("note_covid_count")) > 0:
        score += 15
        feedback_parts.append("DM-101 discrepancy note recorded (+15)")
    else:
        feedback_parts.append("FAIL: DM-101 discrepancy note not found")

    # 4. Check DM-102
    dm102_status = _safe_int(result.get("dm102_status_id"))
    if dm102_status in valid_statuses:
        score += 10
        feedback_parts.append("DM-102 event status updated successfully (+10)")
    else:
        feedback_parts.append(f"FAIL: DM-102 event status is {dm102_status} (expected 5 or 6)")

    if _safe_int(result.get("note_transportation_count")) > 0:
        score += 15
        feedback_parts.append("DM-102 discrepancy note recorded (+15)")
    else:
        feedback_parts.append("FAIL: DM-102 discrepancy note not found")

    # 5. Check DM-103
    dm103_status = _safe_int(result.get("dm103_status_id"))
    if dm103_status in valid_statuses:
        score += 10
        feedback_parts.append("DM-103 event status updated successfully (+10)")
    else:
        feedback_parts.append(f"FAIL: DM-103 event status is {dm103_status} (expected 5 or 6)")

    if _safe_int(result.get("note_withdrew_count")) > 0:
        score += 15
        feedback_parts.append("DM-103 discrepancy note recorded (+15)")
    else:
        feedback_parts.append("FAIL: DM-103 discrepancy note not found")

    # 6. VLM Visual Verification (Final Screenshot)
    query_vlm = env_info.get("query_vlm")
    final_screenshot = None
    
    # Extract final screenshot from trajectory
    for step in reversed(traj.get("steps", [])):
        if "observation" in step and "image" in step["observation"]:
            final_screenshot = step["observation"]["image"]
            break

    if final_screenshot and query_vlm:
        vlm_res = query_vlm(prompt=_build_vlm_prompt(), image=final_screenshot)
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("openclinica_visible"):
                score += 5
                vlm_criteria = 0
                if parsed.get("matrix_or_subject_view"): vlm_criteria += 1
                if parsed.get("skipped_stopped_indicator"): vlm_criteria += 1
                if parsed.get("discrepancy_note_visible"): vlm_criteria += 1
                
                vlm_bonus = min(20, vlm_criteria * 7)
                score += vlm_bonus
                feedback_parts.append(f"VLM visual check passed (+{5 + vlm_bonus})")
            else:
                feedback_parts.append("VLM: OpenClinica not clearly visible in final state")
    else:
        feedback_parts.append("VLM verification skipped (no screenshot or VLM available)")

    # 7. Audit Log Anti-Gaming Penalty
    baseline_audit = _safe_int(result.get("audit_baseline"))
    current_audit = _safe_int(result.get("audit_current"))
    if current_audit <= baseline_audit and score > 25:
        score = max(0, score - 30)
        feedback_parts.append("PENALTY (-30): No new audit log entries detected (GUI bypassed)")

    # Finalize
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }