#!/usr/bin/env python3
"""
Verifier for professional_signature_and_introduction task.

Verifies:
1. Signature Settings: Checks if signature text exists in application config files.
2. Email Composition: Checks for an email to the correct recipient with correct subject.
3. Signature in Body: Checks if the email body contains the required signature elements.
4. VLM Trajectory: Verifies the user navigated settings and composed the email.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_professional_signature_and_introduction(traj, env_info, task_info):
    """
    Verify the professional signature creation and email introduction task.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    req_sig = metadata.get('required_signature', {})
    req_email = metadata.get('required_email', {})

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Data extraction
    drafts = result.get('drafts', [])
    sent = result.get('sent', [])
    all_emails = drafts + sent
    config_check = result.get('config_persistence', {})

    # ================================================================
    # Criterion 1: Configuration Persistence (25 points)
    # ================================================================
    # Did the agent actually change settings?
    config_hits = 0
    config_hits += 1 if config_check.get("name_found") == "true" else 0
    config_hits += 1 if config_check.get("title_found") == "true" else 0
    config_hits += 1 if config_check.get("company_found") == "true" else 0
    config_hits += 1 if config_check.get("phone_found") == "true" else 0

    if config_hits >= 3:
        score += 25
        feedback_parts.append(f"Signature settings verified ({config_hits}/4 elements in config)")
    elif config_hits >= 1:
        score += 10
        feedback_parts.append(f"Partial signature settings found ({config_hits}/4 elements)")
    else:
        feedback_parts.append("Signature not found in application settings storage")

    # ================================================================
    # Criterion 2: Email Existence & Addressing (30 points)
    # ================================================================
    target_email = None
    
    # Find the best candidate email
    for email in all_emails:
        # Check recipient
        if req_email.get('recipient').lower() in email.get('to', '').lower():
            target_email = email
            break
    
    if target_email:
        score += 15 # Correct recipient
        feedback_parts.append("Email addressed to correct recipient")
        
        # Check subject
        if req_email.get('subject_keyword').lower() in target_email.get('subject', '').lower():
            score += 15
            feedback_parts.append("Subject line correct")
        else:
            feedback_parts.append("Subject line missing keyword 'introduction'")
    elif len(all_emails) > 0:
        feedback_parts.append(f"Email created but sent to wrong recipient: {all_emails[0].get('to')}")
    else:
        feedback_parts.append("No new emails drafted or sent")

    # ================================================================
    # Criterion 3: Signature in Body (25 points)
    # ================================================================
    body_score = 0
    if target_email:
        body_lower = target_email.get('body', '').lower()
        
        elements_found = []
        if req_sig.get('name').lower() in body_lower: elements_found.append("Name")
        if req_sig.get('title').lower() in body_lower: elements_found.append("Title")
        if "techvision" in body_lower: elements_found.append("Company")
        if "555" in body_lower: elements_found.append("Phone")
        
        if len(elements_found) == 4:
            body_score = 25
        elif len(elements_found) == 3:
            body_score = 15
        elif len(elements_found) >= 1:
            body_score = 5
            
        score += body_score
        feedback_parts.append(f"Body contains signature elements: {', '.join(elements_found)}")
    
    # ================================================================
    # Criterion 4: VLM Verification (20 points)
    # ================================================================
    # Check if they actually used the settings menu vs just typing it manually
    query_vlm = env_info.get('query_vlm')
    sample_trajectory_frames = env_info.get('sample_trajectory_frames')
    
    if query_vlm and sample_trajectory_frames and traj:
        frames = sample_trajectory_frames(traj, num_samples=5)
        vlm_res = query_vlm(
            images=frames,
            prompt="""Analyze these screenshots of a user configuring an email client.
            Did the user:
            1. Access a 'Settings', 'Preferences', or 'Signature' menu?
            2. Type text into a signature configuration box?
            3. Compose an email?
            
            Return JSON: {"settings_accessed": bool, "signature_configured": bool, "composed_email": bool}
            """
        )
        parsed = vlm_res.get('parsed', {}) if isinstance(vlm_res, dict) else {}
        
        if parsed.get('settings_accessed') or parsed.get('signature_configured'):
            score += 20
            feedback_parts.append("VLM verified settings navigation")
        elif parsed.get('composed_email'):
            score += 10 # Partial for just composing
            feedback_parts.append("VLM verified email composition only")
    else:
        # Fallback if VLM fails but hard config check passed
        if config_hits >= 3:
            score += 20
            feedback_parts.append("Config verified (VLM skipped)")

    # ================================================================
    # Final Result
    # ================================================================
    passed = score >= 60 and (target_email is not None)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }