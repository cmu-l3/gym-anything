#!/usr/bin/env python3
"""Verifier for correct_patient_misidentification task."""

import json
import tempfile
import os
import logging
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logger = logging.getLogger(__name__)

def _build_vlm_prompt():
    return """Examine these screenshots of an agent operating OpenClinica (a clinical trial management system).

Check the trajectory for the following evidence:
1. Did the agent navigate to the "Subject Matrix" or a subject's event schedule?
2. Did the agent use the "Remove" action (usually a red X icon) or click to invalidate a study event?
3. Did the agent open a Case Report Form (CRF) to enter clinical data (like blood pressure, heart rate, or temperature)?
4. Is OpenClinica visibly running in the browser?

Respond in JSON format:
{
    "openclinica_visible": true/false,
    "subject_matrix_visible": true/false,
    "remove_event_evidence": true/false,
    "data_entry_evidence": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

def verify_correct_patient_misidentification(traj, env_info, task_info):
    """
    Verify the patient data correction workflow.
    
    Scoring (100 pts total):
    - DM-101 Event soft-deleted/removed (status_id = 5 or 7, or deleted = 0): 35 pts
    - DM-102 Event Scheduled/Exists: 15 pts
    - DM-102 Data Entered correctly (142, 88, 76, 37.1, 85.0): up to 30 pts (6 pts per matched value)
    - VLM Trajectory Check: 20 pts
    - GUI bypass penalty: -100 if no audit logs found (direct SQL injection)

    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # --- 1. Load result JSON ---
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/correct_patient_misidentification_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script did not run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # --- 2. Verify Integrity Nonce ---
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
        return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: Result file nonce mismatch."}

    score = 0
    feedback_parts = []

    # --- 3. Evaluate DM-101 Status (35 pts) ---
    # status_id 5 = Removed, 7 = Auto-Removed. 0 means deleted from database.
    dm101_status = result.get('dm101_status_id', 1)
    if dm101_status in [0, 5, 7]:
        score += 35
        feedback_parts.append(f"DM-101 event successfully invalidated (status_id={dm101_status}) (+35)")
    else:
        feedback_parts.append(f"FAIL: DM-101 event was not removed (status_id={dm101_status}) (0/35)")

    # --- 4. Evaluate DM-102 Event Exists (15 pts) ---
    dm102_exists = result.get('dm102_event_exists', False)
    if dm102_exists:
        score += 15
        feedback_parts.append("DM-102 Week 4 event successfully scheduled (+15)")
    else:
        feedback_parts.append("FAIL: DM-102 Week 4 event not found (0/15)")

    # --- 5. Evaluate DM-102 Data Entry (30 pts) ---
    dm102_values_str = result.get('dm102_values', '')
    dm102_values = [v.strip() for v in dm102_values_str.split('|') if v.strip()]
    
    expected_values = ['142', '88', '76', '37.1', '85.0']
    alt_expected_values = ['142.0', '88.0', '76.0', '37', '85'] # Accommodate potential float/int cast formatting
    
    matched_count = 0
    for val, alt_val in zip(expected_values, alt_expected_values):
        if val in dm102_values or alt_val in dm102_values:
            matched_count += 1
            
    points_per_value = 6
    data_score = matched_count * points_per_value
    score += data_score
    
    if matched_count == 5:
        feedback_parts.append(f"All clinical data values entered correctly for DM-102 (+30)")
    elif matched_count > 0:
        feedback_parts.append(f"Partial data entry: {matched_count}/5 values found (+{data_score})")
    else:
        feedback_parts.append("FAIL: Expected clinical data values not found in DM-102 record (0/30)")

    # --- 6. VLM Trajectory Verification (20 pts) ---
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    images = frames + [final] if final else frames
    
    if images:
        vlm_res = query_vlm(prompt=_build_vlm_prompt(), images=images)
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            vlm_score = 0
            
            if parsed.get("openclinica_visible"):
                vlm_score += 5
            if parsed.get("remove_event_evidence") or parsed.get("subject_matrix_visible"):
                vlm_score += 7
            if parsed.get("data_entry_evidence"):
                vlm_score += 8
                
            score += vlm_score
            feedback_parts.append(f"VLM Visual check passed (+{vlm_score}/20)")
        else:
            feedback_parts.append(f"VLM check failed or unavailable (0/20)")
    else:
        feedback_parts.append("No screenshots available for VLM (0/20)")

    # --- 7. Audit Log Penalty ---
    audit_count = result.get('audit_log_count', 0)
    baseline_count = result.get('audit_baseline_count', 0)
    if audit_count <= baseline_count:
        score -= 100
        feedback_parts.append("PENALTY: No GUI interaction detected in audit logs (-100)")

    # Final Evaluation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": max(0, score),
        "feedback": " | ".join(feedback_parts)
    }