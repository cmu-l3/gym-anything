#!/usr/bin/env python3
"""Verifier for manage_subject_dispositions task."""

import json
import tempfile
import os
import logging
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from vlm_utils import query_vlm, sample_trajectory_frames, get_final_screenshot

logger = logging.getLogger(__name__)


def _build_vlm_prompt():
    return """Examine these screenshots of an OpenClinica session.

Check the following:
1. Is the OpenClinica web interface visible?
2. Did the user navigate to subject management or view subject details?
3. Is there visual evidence of subject records for DM-102, DM-104, or DM-105 being viewed or modified?
4. Are there any confirmation banners or success messages indicating a status change (e.g., 'Subject removed', 'Subject restored')?

Respond in JSON format:
{
    "openclinica_visible": true/false,
    "subject_management_visible": true/false,
    "target_subjects_visible": true/false,
    "success_message_visible": true/false,
    "confidence": "low"/"medium"/"high"
}
"""


def verify_manage_subject_dispositions(traj, env_info, task_info):
    """
    Verify subject dispositions were correctly updated.

    Scoring (100 points total):
    - DM-102 removed (status != 1): 25 pts
    - DM-105 removed (status != 1): 25 pts
    - DM-104 restored (status == 1): 30 pts
    - Control subjects (101, 103) changed: -15 penalty
    - Audit log penalty (no interaction): -20 penalty
    - VLM visual check (trajectory + final): up to 10 pts

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/manage_subject_dispositions_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Verify nonce integrity
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

    statuses = result.get('statuses', {})
    score = 0
    feedback_parts = []

    # 1. Check DM-102 (Removed)
    st_102 = statuses.get("DM-102", 1)
    if st_102 != 1:
        score += 25
        feedback_parts.append(f"DM-102 successfully removed (status={st_102}) [+25]")
    else:
        feedback_parts.append("FAIL: DM-102 was not removed [0/25]")

    # 2. Check DM-105 (Removed)
    st_105 = statuses.get("DM-105", 1)
    if st_105 != 1:
        score += 25
        feedback_parts.append(f"DM-105 successfully removed (status={st_105}) [+25]")
    else:
        feedback_parts.append("FAIL: DM-105 was not removed [0/25]")

    # 3. Check DM-104 (Restored)
    st_104 = statuses.get("DM-104", 5)
    if st_104 == 1:
        score += 30
        feedback_parts.append("DM-104 successfully restored to active [+30]")
    else:
        feedback_parts.append(f"FAIL: DM-104 was not restored (status={st_104}) [0/30]")

    # 4. Check control subjects
    st_101 = statuses.get("DM-101", 1)
    st_103 = statuses.get("DM-103", 1)
    if st_101 != 1 or st_103 != 1:
        score -= 15
        feedback_parts.append("PENALTY: Control subjects (DM-101 or DM-103) were incorrectly modified [-15]")
    else:
        feedback_parts.append("Control subjects remain intact")

    # 5. Audit log check (anti-gaming)
    audit_count = result.get('audit_log_count', 0)
    audit_baseline = result.get('audit_baseline_count', 0)
    if audit_count <= audit_baseline:
        score -= 20
        feedback_parts.append("PENALTY: No GUI audit log entries detected (direct DB manipulation?) [-20]")

    # 6. VLM visual check
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)
    
    if frames:
        vlm_res = query_vlm(prompt=_build_vlm_prompt(), images=frames)
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            vlm_score = 0
            if parsed.get("subject_management_visible"): vlm_score += 4
            if parsed.get("target_subjects_visible"): vlm_score += 3
            if parsed.get("success_message_visible"): vlm_score += 3
            
            if parsed.get("confidence") == "high":
                pass
            elif parsed.get("confidence") == "medium":
                vlm_score = int(vlm_score * 0.8)
            else:
                vlm_score = int(vlm_score * 0.5)
                
            score += vlm_score
            feedback_parts.append(f"VLM Visual Check: +{vlm_score} pts")
        else:
            feedback_parts.append("VLM query failed")
    else:
        feedback_parts.append("No frames available for VLM check")

    score = max(0, min(100, score))
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }