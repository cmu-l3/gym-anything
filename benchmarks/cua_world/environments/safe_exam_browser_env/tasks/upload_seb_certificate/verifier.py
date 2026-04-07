#!/usr/bin/env python3
"""
Verifier for upload_seb_certificate task.

Verification Strategy:
1. DB Check: Checks if the certificate record count increased and if a certificate matching the alias 'UniversityExamCert2025' exists.
2. VLM Check (Trajectory): Verifies the agent navigated to the Certificates menu, interacted with a file upload dialog, and reached a success state.
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_upload_seb_certificate(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve task results safely
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ================================================================
    # 1. Database Evidence (40 points max)
    # ================================================================
    target_cert_exists = result.get('target_cert_exists', False)
    new_certs = result.get('new_certs_created', 0)
    db_evidence = False

    if target_cert_exists:
        score += 40
        feedback_parts.append("Target certificate alias found in database")
        db_evidence = True
    elif new_certs > 0:
        score += 20
        feedback_parts.append(f"New certificate created (+{new_certs}), but alias mismatch")
        db_evidence = True
    else:
        feedback_parts.append("No new certificate found in database")

    # ================================================================
    # 2. VLM Trajectory Evidence (60 points max)
    # ================================================================
    frames = sample_trajectory_frames(traj, n=5)
    final = get_final_screenshot(traj)
    images = frames + [final] if final else frames
    
    if images:
        vlm_prompt = """
        You are verifying a web automation task in Safe Exam Browser (SEB) Server. 
        The agent was tasked with uploading an identity certificate file ('seb_exam_cert.pem') and setting its alias/name to 'UniversityExamCert2025'.
        
        Analyze these trajectory frames and determine:
        1. Did the user navigate to the Certificate management section?
        2. Is there evidence of a file upload dialog being used or a file being selected?
        3. Does the final or near-final screen show the certificate list with 'UniversityExamCert2025' visible?
        
        Respond strictly with a JSON object in this format:
        {
            "navigated_to_certificates": true/false,
            "used_file_upload": true/false,
            "cert_visible_in_list": true/false,
            "reasoning": "Brief explanation"
        }
        """
        
        vlm_result = query_vlm(images=images, prompt=vlm_prompt)
        parsed = {}
        
        # Robust parsing of VLM output
        if isinstance(vlm_result, dict):
            parsed = vlm_result.get("parsed", vlm_result)
        else:
            try:
                match = re.search(r'\{.*\}', vlm_result, re.DOTALL)
                if match:
                    parsed = json.loads(match.group(0))
            except Exception as e:
                logger.error(f"Failed to parse VLM JSON string: {e}")
                
        # Score VLM criteria
        if parsed.get("navigated_to_certificates", False):
            score += 10
            feedback_parts.append("VLM: Navigated to certificates")
            
        if parsed.get("used_file_upload", False):
            score += 20
            feedback_parts.append("VLM: Used file upload")
            
        if parsed.get("cert_visible_in_list", False):
            score += 30
            feedback_parts.append("VLM: Certificate visible in UI list")
    else:
        feedback_parts.append("No images available for VLM verification")

    # ================================================================
    # Verification Decision
    # ================================================================
    # Pass requires either perfect VLM execution or DB existence + partial VLM
    key_criteria_met = db_evidence or parsed.get("cert_visible_in_list", False)
    passed = score >= 60 and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }