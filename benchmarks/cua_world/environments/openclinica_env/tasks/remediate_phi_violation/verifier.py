#!/usr/bin/env python3
"""Verifier for remediate_phi_violation task."""

import json
import tempfile
import os
import logging
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from vlm_utils import query_vlm, sample_trajectory_frames, get_final_screenshot

logger = logging.getLogger(__name__)

def _build_vlm_prompt():
    return """Examine these screenshots showing an agent interacting with OpenClinica (a clinical trial management system).

Check the following:
1. Did the agent navigate to the "Boston Heart Institute" site context or Study/Site Administration?
2. Did the agent access the "Update Subject" or subject matrix page?
3. Is there evidence that the agent interacted with Subject IDs (like CV-301, CV-302) or Secondary IDs?
4. Is there evidence that the agent edited the site/facility details?

Respond in JSON format:
{
    "interacted_with_subjects": true/false,
    "interacted_with_site_details": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""

def verify_remediation(traj, env_info, task_info):
    """
    Verify the remediation of PHI and site flagging.

    Scoring (100 pts total):
    - PHI completely eradicated (MRNs and names removed) : 20 pts
    - CV-301 correctly labeled and secondary cleared       : 15 pts
    - CV-302 correctly labeled and secondary cleared       : 15 pts
    - CV-303 correctly labeled and secondary cleared       : 15 pts
    - Site facility name contains "CAPA ACTIVE"          : 15 pts
    - VLM Trajectory Verification                        : 20 pts
    - Penalty: No UI interaction via audit logs          : -100 pts (Fail)
    
    Pass threshold: 75 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # --- Read Results ---
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/phi_remediation_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script did not run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # --- Integrity Check ---
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
        return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: Nonce mismatch"}

    score = 0
    feedback = []

    # --- Criterion 1: PHI Eradicated (20 pts) ---
    mrn_count = result.get('mrn_count', 99)
    phi_count = result.get('phi_names_count', 99)
    
    if mrn_count == 0 and phi_count == 0:
        score += 20
        feedback.append("PHI completely eradicated (+20)")
    else:
        feedback.append(f"FAIL: {mrn_count} MRNs and {phi_count} names still exist (0/20)")

    # --- Criteria 2-4: Correct Subject Identification & Clearing (15 pts each) ---
    for cv_id in ["cv301", "cv302", "cv303"]:
        subj_data = result.get(cv_id, {})
        target_name = cv_id.upper().replace("CV", "CV-")
        if subj_data.get('found') and subj_data.get('sec_cleared'):
            score += 15
            feedback.append(f"{target_name} correctly updated and Secondary ID cleared (+15)")
        elif subj_data.get('found'):
            feedback.append(f"FAIL: {target_name} found, but Secondary ID was not cleared! (0/15)")
        else:
            feedback.append(f"FAIL: {target_name} not found in database (0/15)")

    # --- Criterion 5: Site Flag (15 pts) ---
    facility = result.get('facility_name', '')
    if 'CAPA ACTIVE' in facility.upper():
        score += 15
        feedback.append(f"Site facility name correctly flagged: '{facility}' (+15)")
    else:
        feedback.append(f"FAIL: Site facility name '{facility}' missing 'CAPA ACTIVE' (0/15)")

    # --- Criterion 6: VLM Trajectory Verification (20 pts) ---
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_shot = get_final_screenshot(traj)
        images = frames + [final_shot] if final_shot else frames
        
        if images and env_info.get('query_vlm'):
            vlm_res = env_info['query_vlm'](prompt=_build_vlm_prompt(), images=images)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('interacted_with_subjects'): vlm_score += 10
                if parsed.get('interacted_with_site_details'): vlm_score += 10
                
                confidence = parsed.get('confidence', 'low')
                if confidence == 'low': vlm_score = int(vlm_score * 0.5)
                elif confidence == 'medium': vlm_score = int(vlm_score * 0.8)
                
                score += vlm_score
                feedback.append(f"VLM Verification: {vlm_score}/20 pts")
            else:
                feedback.append("VLM Verification failed, skipping bonus.")
    except Exception as e:
        logger.error(f"VLM error: {e}")
        feedback.append("VLM Verification encountered an error.")

    # --- Criterion 7: Anti-Gaming Audit Log Penalty ---
    audit_base = int(result.get('audit_baseline', 0))
    audit_curr = int(result.get('audit_current', 0))
    if (audit_curr - audit_base) < 3:
        score -= 100
        feedback.append("PENALTY: Insufficient UI interaction detected. Audit logs show direct DB manipulation (-100)")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": max(0, score),
        "feedback": " | ".join(feedback)
    }