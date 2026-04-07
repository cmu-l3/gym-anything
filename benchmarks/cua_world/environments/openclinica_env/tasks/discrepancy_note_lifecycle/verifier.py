#!/usr/bin/env python3
"""Verifier for discrepancy_note_lifecycle task."""

import json
import tempfile
import os
import logging
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logger = logging.getLogger(__name__)

def _build_vlm_prompt():
    return """Examine this screenshot of OpenClinica (a clinical trial management system).

Check the following:
1. Is OpenClinica visible in Firefox (not an error page, login page, or blank page)?
2. Is the "Notes & Discrepancies" page, a discrepancy note dialog, or a subject record visible?
3. Is there evidence of managing discrepancy notes (queries, annotations, flags)?
4. Can you see any success messages or note details like "Enrollment date", "Informed consent", or "Verified against source"?

Respond in JSON format:
{
    "openclinica_visible": true/false,
    "discrepancy_ui_visible": true/false,
    "note_management_evidence": true/false,
    "relevant_text_visible": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

def verify_discrepancy_note_lifecycle(traj, env_info, task_info):
    """
    Verify discrepancy_note_lifecycle task completion.
    
    Scoring:
    - DM-101 Query exists: 25 pts
    - DM-101 is type Query (3): 5 pts
    - DM-102 Annotation exists: 20 pts
    - DM-102 is type Annotation (2): 5 pts
    - DM-103 query closed: 25 pts
    - DM-103 has closing comment: 5 pts
    - VLM trajectory check: 10 pts
    - Audit log penalty: -20 if no GUI interaction
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/discrepancy_note_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script did not run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Integrity check
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
        return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: Result file nonce mismatch — possible tampering"}

    score = 0
    feedback_parts = []

    # 1. DM-101 Query
    dm101_exists = result.get('dm101_note_exists', False)
    dm101_desc = result.get('dm101_note_desc', '').lower()
    dm101_type = str(result.get('dm101_note_type', ''))
    
    if dm101_exists and 'enrollment date' in dm101_desc:
        score += 25
        feedback_parts.append("DM-101 Query exists (+25)")
        if dm101_type == '3':
            score += 5
            feedback_parts.append("DM-101 note is type Query (+5)")
        else:
            feedback_parts.append(f"DM-101 note is type {dm101_type} (expected 3=Query)")
    elif dm101_exists:
        score += 15
        feedback_parts.append("DM-101 Note exists but description lacks 'enrollment date' (+15)")
        if dm101_type == '3':
            score += 5
            feedback_parts.append("DM-101 note is type Query (+5)")
    else:
        feedback_parts.append("FAIL: DM-101 note not found (0/30)")

    # 2. DM-102 Annotation
    dm102_exists = result.get('dm102_note_exists', False)
    dm102_desc = result.get('dm102_note_desc', '').lower()
    dm102_type = str(result.get('dm102_note_type', ''))
    
    if dm102_exists and 'informed consent' in dm102_desc:
        score += 20
        feedback_parts.append("DM-102 Annotation exists (+20)")
        if dm102_type == '2':
            score += 5
            feedback_parts.append("DM-102 note is type Annotation (+5)")
        else:
            feedback_parts.append(f"DM-102 note is type {dm102_type} (expected 2=Annotation)")
    elif dm102_exists:
        score += 10
        feedback_parts.append("DM-102 Note exists but description lacks 'informed consent' (+10)")
        if dm102_type == '2':
            score += 5
            feedback_parts.append("DM-102 note is type Annotation (+5)")
    else:
        feedback_parts.append("FAIL: DM-102 note not found (0/25)")

    # 3. DM-103 Closed
    dm103_closed = result.get('dm103_query_closed', False)
    dm103_has_comment = result.get('dm103_has_comment', False)
    
    if dm103_closed:
        score += 25
        feedback_parts.append("DM-103 query closed (+25)")
        if dm103_has_comment:
            score += 5
            feedback_parts.append("DM-103 closing comment present (+5)")
        else:
            feedback_parts.append("DM-103 lacks expected closing comment")
    else:
        feedback_parts.append("FAIL: DM-103 query not closed (0/30)")

    # Audit log check
    audit_count = result.get('audit_log_count', 0)
    audit_baseline = result.get('audit_baseline_count', 0)
    if audit_count <= audit_baseline:
        score -= 20
        feedback_parts.append("PENALTY: No GUI interaction detected in audit log (-20)")

    # VLM Verification
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    final_screenshot = get_final_screenshot(traj)
    frames = sample_trajectory_frames(traj, n=3)
    
    if query_vlm and (final_screenshot or frames):
        images_to_check = frames + [final_screenshot] if final_screenshot else frames
        # Just check the final frame for visual context
        vlm_result = query_vlm(prompt=_build_vlm_prompt(), image=images_to_check[-1])
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("discrepancy_ui_visible") or parsed.get("note_management_evidence"):
                vlm_score += 10
                feedback_parts.append("VLM visual evidence verified (+10)")
            else:
                feedback_parts.append("VLM found no strong visual evidence")
    
    score += vlm_score

    score = max(0, min(100, score))
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }