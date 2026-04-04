#!/usr/bin/env python3
"""
Verifier for send_provider_message task in Oscar EMR.
Verifies that a message was correctly sent via database records and VLM trajectory.
"""

import json
import os
import logging
import tempfile
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM utils provided by the environment
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    logger.warning("gym_anything.vlm not available - skipping VLM checks")
    VLM_AVAILABLE = False

def verify_send_provider_message(traj, env_info, task_info):
    """
    Verify the agent sent the correct provider message.
    
    Scoring:
    - Database Verification (70 pts):
        - Message exists (10 pts)
        - Correct Subject (15 pts)
        - Correct Recipient (25 pts)
        - Correct Body Content (20 pts)
    - VLM Verification (30 pts):
        - Workflow progression (login -> messenger -> compose) (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_recipient = metadata.get('recipient_provider_no', '100001')
    subject_keyword = metadata.get('subject_keyword', 'Cardiology Referral')
    body_keywords = metadata.get('body_keywords', ['Margaret Thompson', 'dyspnea'])

    # 1. Retrieve Database Results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            db_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        db_result = {"found": False}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # --- Database Verification ---
    if db_result.get("found"):
        score += 10
        feedback.append("New message found in database.")
        
        # Check Recipient
        actual_recipient = db_result.get("recipient", "")
        if actual_recipient == expected_recipient:
            score += 25
            feedback.append("Recipient is correct (Dr. James Wilson).")
        else:
            feedback.append(f"Incorrect recipient ID. Expected {expected_recipient}, got {actual_recipient}.")
            
        # Check Subject
        actual_subject = db_result.get("subject", "")
        if subject_keyword.lower() in actual_subject.lower():
            score += 15
            feedback.append(f"Subject contains '{subject_keyword}'.")
        else:
            feedback.append(f"Subject mismatch. Expected keyword '{subject_keyword}', got '{actual_subject}'.")
            
        # Check Body
        actual_body = db_result.get("body", "")
        keywords_found = [k for k in body_keywords if k.lower() in actual_body.lower()]
        if len(keywords_found) == len(body_keywords):
            score += 20
            feedback.append("Message body contains all required clinical details.")
        elif len(keywords_found) > 0:
            partial_score = int(20 * (len(keywords_found) / len(body_keywords)))
            score += partial_score
            feedback.append(f"Message body missing some details. Found: {keywords_found}.")
        else:
            feedback.append("Message body does not contain required clinical keywords.")
            
    else:
        feedback.append("No new message sent by the provider found in database.")

    # --- VLM Verification (Trajectory) ---
    vlm_score = 0
    if VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            all_frames = frames + [final_frame] if final_frame else frames
            
            prompt = """
            Analyze these screenshots of a user interacting with Oscar EMR.
            The goal is to send an internal message to another provider.
            
            Look for these stages:
            1. Login screen or Dashboard.
            2. 'Messenger' or 'Msg' window/popup.
            3. A 'Compose Message' interface with fields for 'To', 'Subject', and 'Body'.
            4. Text being entered related to a "Cardiology Referral".
            
            Did the agent navigate to the messaging system and attempt to write a message?
            Reply with JSON: {"workflow_detected": boolean, "confidence": "high|medium|low"}
            """
            
            vlm_result = query_vlm(images=all_frames, prompt=prompt)
            
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                if parsed.get('workflow_detected', False):
                    vlm_score = 30
                    feedback.append("VLM confirmed messaging workflow.")
                else:
                    feedback.append("VLM did not detect messaging workflow.")
            else:
                # Fallback if VLM fails but DB was perfect
                if score >= 60:
                    vlm_score = 30
                    feedback.append("VLM unavailable, defaulting to pass based on strong DB evidence.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            if score >= 60:
                vlm_score = 30
    
    score += vlm_score

    # Final Pass Determination
    # Must have found the message in DB AND got correct recipient to pass
    passed = (score >= 70) and db_result.get("found") and (db_result.get("recipient") == expected_recipient)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }