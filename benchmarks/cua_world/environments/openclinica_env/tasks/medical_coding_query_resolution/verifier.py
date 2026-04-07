#!/usr/bin/env python3
"""Verifier for medical_coding_query_resolution task."""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logger = logging.getLogger(__name__)

def _build_vlm_prompt():
    return """Examine these screenshots from a session where a user is performing medical coding in OpenClinica.

Check the following:
1. Did the user open or view the CSV file (meddra_extract.csv) in a text editor, terminal, or spreadsheet app?
2. Did the user navigate to the Notes & Discrepancies module in OpenClinica?
3. Did the user open any Discrepancy Note threads (viewing the query details and response boxes)?

Respond in JSON format:
{
    "csv_file_viewed": true/false,
    "notes_module_viewed": true/false,
    "discrepancy_thread_viewed": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

def verify_medical_coding(traj, env_info, task_info):
    """
    Verify the medical coding task completion.
    
    Scoring structure (100 pts):
    - CV-101 coded and status updated (25 pts)
    - CV-102 coded and status updated (25 pts)
    - CV-103 coded and status updated (25 pts)
    - VLM Trajectory check confirming workflow (up to 25 pts)
    - Anti-gaming penalty if no GUI interaction detected (-30 pts)
    
    Pass threshold: 75 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/medical_coding_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # Result integrity verification
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
            
    if expected_nonce and result.get('result_nonce', '') != expected_nonce:
        return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: Result file nonce mismatch."}

    score = 0
    feedback_parts = []
    
    # Check CV-101
    cv101 = result.get('cv101', {})
    if cv101.get('code_found') and cv101.get('status_id') != 1:
        score += 25
        feedback_parts.append("✅ CV-101 correctly coded (Nausea -> 10028813) (+25)")
    else:
        feedback_parts.append("❌ CV-101 NOT properly coded or status remains 'New' (0/25)")
        
    # Check CV-102
    cv102 = result.get('cv102', {})
    if cv102.get('code_found') and cv102.get('status_id') != 1:
        score += 25
        feedback_parts.append("✅ CV-102 correctly coded (Headache -> 10019211) (+25)")
    else:
        feedback_parts.append("❌ CV-102 NOT properly coded or status remains 'New' (0/25)")
        
    # Check CV-103
    cv103 = result.get('cv103', {})
    if cv103.get('code_found') and cv103.get('status_id') != 1:
        score += 25
        feedback_parts.append("✅ CV-103 correctly coded (Dizziness -> 10013573) (+25)")
    else:
        feedback_parts.append("❌ CV-103 NOT properly coded or status remains 'New' (0/25)")

    # VLM Verification of Trajectory
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        try:
            frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            images = frames + [final_frame] if final_frame else frames
            
            if images:
                vlm_res = query_vlm(prompt=_build_vlm_prompt(), images=images)
                if vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    vlm_score = 0
                    if parsed.get('csv_file_viewed'): vlm_score += 10
                    if parsed.get('notes_module_viewed'): vlm_score += 5
                    if parsed.get('discrepancy_thread_viewed'): vlm_score += 10
                    
                    score += vlm_score
                    feedback_parts.append(f"VLM visual evidence score: {vlm_score}/25")
                else:
                    feedback_parts.append("VLM query failed, skipping visual verification.")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            feedback_parts.append("VLM error during trajectory analysis.")
            
    # Audit log penalty check
    audit_count = result.get('audit_log_count', 0)
    baseline_count = result.get('audit_baseline_count', 0)
    if audit_count <= baseline_count and score > 0:
        score -= 30
        feedback_parts.append("PENALTY: No application audit logs detected, possible GUI bypass (-30)")
        
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": max(0, min(100, score)),
        "feedback": " | ".join(feedback_parts)
    }