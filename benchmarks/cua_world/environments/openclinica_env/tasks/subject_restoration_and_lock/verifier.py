#!/usr/bin/env python3
"""Verifier for subject_restoration_and_lock task."""

import json
import tempfile
import os
import logging
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from vlm_utils import sample_trajectory_frames, get_final_screenshot, query_vlm

logger = logging.getLogger(__name__)


def _build_vlm_prompt():
    return """Examine these screenshots of an OpenClinica session.

Check the following:
1. Is OpenClinica visible?
2. Is there evidence that the user navigated to subject 'DM-105' (e.g., in the subject matrix, viewing details, or performing an action on it)?
3. Can you see a lock icon, restore icon, or a confirmation message regarding subject restoration or event locking?

Respond in JSON format:
{
    "openclinica_visible": true/false,
    "target_subject_visible": true/false,
    "action_evidence_visible": true/false,
    "confidence": "low"/"medium"/"high"
}
"""


def _safe_int(value, default=0):
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        try:
            return int(value.strip())
        except (ValueError, AttributeError):
            return default
    return default


def verify_subject_restoration_and_lock(traj, env_info, task_info):
    """
    Verify subject_restoration_and_lock task completion.

    Scoring (100 points total):
    - Criterion 1: DM-105 Subject restored (status_id = 1): 40 pts
    - Criterion 2: DM-105 Baseline event locked (subject_event_status_id = 7): 40 pts
    - Criterion 3: Precision bonus - DM-101 untouched: 10 pts
    - Criterion 4: VLM visual verification of workflow: 10 pts
    - Audit Penalty: -100 if DB values changed but no audit trail exists.
    
    Pass threshold: 80 points.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load Result Data
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/subject_restoration_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Verify Nonce Integrity
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
        return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: Nonce mismatch — tampering detected"}

    score = 0
    feedback_parts = []

    dm105_status = _safe_int(result.get('dm105_status_id', 0))
    dm105_event_status = _safe_int(result.get('dm105_event_status_id', 0))
    dm101_status = _safe_int(result.get('dm101_status_id', 0))
    dm101_event_status = _safe_int(result.get('dm101_event_status_id', 0))

    audit_current = _safe_int(result.get('audit_log_count', 0))
    audit_baseline = _safe_int(result.get('audit_baseline_count', 0))

    # Criterion 1: Subject DM-105 Restored
    subject_restored = False
    if dm105_status == 1:
        score += 40
        subject_restored = True
        feedback_parts.append("✅ Subject DM-105 successfully restored to Available (40/40)")
    elif dm105_status == 6:
        feedback_parts.append("❌ Subject DM-105 was LOCKED instead of restored/available. Read instructions carefully! (0/40)")
    elif dm105_status == 5:
        feedback_parts.append("❌ Subject DM-105 is still marked as Removed (0/40)")
    else:
        feedback_parts.append(f"❌ Subject DM-105 has incorrect status {dm105_status} (0/40)")

    # Criterion 2: Baseline event Locked
    event_locked = False
    if dm105_event_status == 7:
        score += 40
        event_locked = True
        feedback_parts.append("✅ DM-105 Baseline Assessment event successfully Locked (40/40)")
    elif dm105_event_status == 4:
        feedback_parts.append("❌ DM-105 Baseline Assessment event is still Completed, not Locked (0/40)")
    else:
        feedback_parts.append(f"❌ DM-105 Baseline Assessment event has incorrect status {dm105_event_status} (0/40)")

    # Criterion 3: Collateral damage check (DM-101)
    if dm101_status == 1 and dm101_event_status == 4:
        score += 10
        feedback_parts.append("✅ Precision bonus: No collateral damage to DM-101 (+10)")
    else:
        feedback_parts.append(f"❌ Collateral damage detected on DM-101. Status: {dm101_status}, Event: {dm101_event_status} (0/10)")

    # Criterion 4: VLM verification
    frames = sample_trajectory_frames(traj, n=3)
    final = get_final_screenshot(traj)
    if final and env_info.get("query_vlm"):
        vlm_images = frames + [final] if final not in frames else frames
        vlm_result = query_vlm(prompt=_build_vlm_prompt(), images=vlm_images)
        
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("target_subject_visible") or parsed.get("action_evidence_visible"):
                score += 10
                feedback_parts.append("✅ VLM confirmed visual workflow execution (+10)")
            else:
                feedback_parts.append("⚠️ VLM could not confidently confirm target workflow in UI (+0)")
        else:
            feedback_parts.append("⚠️ VLM verification failed (+0)")

    # Anti-gaming: Ensure audit logs show interaction if state changed
    state_changed = (dm105_status != 5) or (dm105_event_status != 4)
    audit_diff = audit_current - audit_baseline
    if state_changed and audit_diff <= 0:
        score -= 100
        feedback_parts.append("❌ FRAUD PENALTY: Database state changed but no GUI interactions detected in audit logs (-100)")

    passed = score >= 80 and subject_restored and event_locked

    return {
        "passed": passed,
        "score": max(0, score),
        "feedback": "\n".join(feedback_parts)
    }