#!/usr/bin/env python3
"""Verifier for subject_site_transfer task."""

import json
import tempfile
import os
import logging
import sys

# Ensure vlm_utils can be imported
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from vlm_utils import query_vlm, sample_trajectory_frames, get_final_screenshot

logger = logging.getLogger(__name__)

def _build_vlm_prompt():
    return """You are evaluating an agent that is transferring a patient ('DM-105') to a new clinical site ('New York Hub') in OpenClinica.
Look at the provided trajectory frames and final screenshot.

Please determine:
1. Is there evidence the agent opened the 'Reassign Subject', 'Transfer Subject', or Study Subject update UI?
2. Are there any UI confirmation banners or success messages indicating that a subject was successfully reassigned or updated?

Respond strictly in JSON format:
{
    "reassign_ui_visible": true/false,
    "success_message_visible": true/false,
    "confidence": "low"/"medium"/"high"
}"""

def verify_subject_site_transfer(traj, env_info, task_info):
    """
    Verify the subject_site_transfer task completion.
    
    Scoring Strategy (100 points total):
    - Primary: DM-105 study_id == NY_ID (50 points)
    - Secondary: Demographics (DOB/Gender) match baseline (20 points)
    - VLM Verification: Agent used UI / Success message seen (30 points)
    - Penalty: If no audit log changes occurred, deduct 100 points (GUI bypass)
    
    Pass Threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Fetch JSON result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/subject_site_transfer_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script did not run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Verify nonce to prevent tampering
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
        return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: Result file nonce mismatch"}

    score = 0
    feedback_parts = []
    
    bos_id = str(result.get('bos_site_id', '0'))
    ny_id = str(result.get('ny_site_id', '0'))
    dm105_study_id = str(result.get('dm105_study_id', '0'))
    
    # 3. Check Primary Criteria: Site Transfer (50 points)
    if dm105_study_id == ny_id and ny_id != '0':
        score += 50
        feedback_parts.append("Success: DM-105 is assigned to the New York Hub (+50 pts)")
    elif dm105_study_id == bos_id:
        feedback_parts.append("Fail: DM-105 is still assigned to the Boston Clinic (0/50 pts)")
    else:
        feedback_parts.append(f"Fail: DM-105 is assigned to an unexpected study/site ID ({dm105_study_id}) (0/50 pts)")

    # 4. Check Secondary Criteria: Demographics Intact (20 points)
    gender = result.get('dm105_gender', '').strip().lower()
    dob = result.get('dm105_dob', '').strip()
    
    demo_score = 0
    if gender in ['m', 'male']:
        demo_score += 10
    else:
        feedback_parts.append("Warning: DM-105 gender was modified or lost")
        
    if '1982' in dob and '05' in dob:
        demo_score += 10
    else:
        feedback_parts.append("Warning: DM-105 DOB was modified or lost")
        
    if demo_score == 20:
        feedback_parts.append("Success: Subject demographics remained intact (+20 pts)")
    score += demo_score

    # 5. Anti-gaming check: Audit Logs
    audit_diff = result.get('audit_diff', 0)
    if audit_diff <= 0:
        score -= 100
        feedback_parts.append("PENALTY: No audit log events detected. Task was failed due to bypassing the OpenClinica GUI (-100 pts)")

    # 6. VLM Trajectory Verification (30 points)
    vlm_score = 0
    query_vlm_func = env_info.get('query_vlm')
    
    if query_vlm_func:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            if final_frame:
                frames.append(final_frame)
                
            if frames:
                vlm_res = query_vlm_func(prompt=_build_vlm_prompt(), images=frames)
                if vlm_res and vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    ui_visible = parsed.get("reassign_ui_visible", False)
                    success_visible = parsed.get("success_message_visible", False)
                    
                    if ui_visible:
                        vlm_score += 15
                        feedback_parts.append("VLM verified Reassign UI was used (+15 pts)")
                    if success_visible:
                        vlm_score += 15
                        feedback_parts.append("VLM verified Success Message (+15 pts)")
                else:
                    feedback_parts.append(f"VLM verification failed: {vlm_res.get('error', 'unknown')}")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            feedback_parts.append("VLM verification exception caught")
    else:
        feedback_parts.append("VLM function unavailable")

    score += vlm_score
    
    # Cap score boundaries
    score = max(0, min(100, score))
    passed = score >= 70 and dm105_study_id == ny_id and audit_diff > 0

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }