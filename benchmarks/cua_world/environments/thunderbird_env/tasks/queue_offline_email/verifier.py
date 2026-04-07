#!/usr/bin/env python3
"""
Verifier for queue_offline_email task.

HYBRID MULTI-SIGNAL VERIFICATION:
1. Thunderbird was put into Offline Mode (prefs.js) - 15 points
2. Email is successfully queued in Unsent Messages (Outbox) - 35 points
3. Email contains correct recipient, subject, and body - 15 points
4. Email is NOT accidentally saved in Drafts or Sent - 15 points
5. VLM: Trajectory frames confirm the agent clicked Offline/Send Later - 20 points
"""

import os
import json
import logging
import mailbox
import tempfile

# Adjust path to find VLM utils from gym_anything
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / 'utils'))

try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are analyzing a sequence of screenshots from an agent operating Mozilla Thunderbird.
The agent was instructed to:
1. Put Thunderbird into Offline Mode.
2. Compose an email.
3. Queue it using "Send Later" (Outbox).

Look at these trajectory frames and assess:
1. OFFLINE_TOGGLED: Is there evidence the agent interacted with the Offline menu (File > Offline) or clicked the connection icon in the status bar?
2. SEND_LATER_USED: Did the agent use the "Send Later" function (often visible in File > Send Later, or indicated by a prompt/dialog about queuing messages)?
3. WORKFLOW_PROGRESS: Does the sequence show composing an email and successfully completing it?

Respond in JSON format:
{
    "offline_toggled": true/false,
    "send_later_used": true/false,
    "workflow_progress": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of visible evidence"
}
"""

def get_email_body(msg):
    """Extracts plain text body from an email message."""
    if msg.is_multipart():
        for part in msg.walk():
            if part.get_content_type() == 'text/plain':
                payload = part.get_payload(decode=True)
                return payload.decode('utf-8', errors='ignore') if payload else ""
    else:
        payload = msg.get_payload(decode=True)
        return payload.decode('utf-8', errors='ignore') if payload else ""
    return ""

def search_mbox_for_subject(mbox_path, target_subject):
    """Parses mbox file and returns message if subject matches."""
    if not os.path.exists(mbox_path) or os.path.getsize(mbox_path) == 0:
        return None
        
    try:
        mbox = mailbox.mbox(mbox_path)
        for msg in mbox:
            subject = msg.get('Subject', '')
            if subject and target_subject.lower() in subject.lower():
                return msg
    except Exception as e:
        logger.error(f"Error parsing mbox {mbox_path}: {e}")
    return None

def count_mbox_messages(mbox_path):
    if not os.path.exists(mbox_path) or os.path.getsize(mbox_path) == 0:
        return 0
    try:
        mbox = mailbox.mbox(mbox_path)
        return len(mbox)
    except Exception:
        return 0

def verify_queue_offline_email(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_recipient = metadata.get('expected_recipient', 'executive.team@company.com')
    expected_subject = metadata.get('expected_subject', 'Q3 Analysis Complete')
    expected_keywords = metadata.get('expected_body_keywords', ['Q3 analysis is complete', 'better connection'])

    score = 0
    feedback_parts = []
    
    # 1. Retrieve the exported JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task_result.json: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Retrieve the copied mbox files
    mbox_unsent = tempfile.NamedTemporaryFile(delete=False)
    mbox_drafts = tempfile.NamedTemporaryFile(delete=False)
    mbox_sent = tempfile.NamedTemporaryFile(delete=False)
    
    try:
        copy_from_env("/tmp/Unsent_Messages", mbox_unsent.name)
        copy_from_env("/tmp/Drafts", mbox_drafts.name)
        copy_from_env("/tmp/Sent", mbox_sent.name)
        
        # --- CRITERION 1: Offline Mode (15 points) ---
        if result.get('offline_mode_active', False):
            score += 15
            feedback_parts.append("Offline mode verified via prefs.js")
        else:
            feedback_parts.append("Thunderbird was not put into Offline mode")

        # --- CRITERION 2: Queued in Unsent Messages (35 points) ---
        unsent_msg = search_mbox_for_subject(mbox_unsent.name, expected_subject)
        initial_unsent = result.get('initial_unsent_count', 0)
        current_unsent = count_mbox_messages(mbox_unsent.name)
        
        if unsent_msg and current_unsent > initial_unsent:
            score += 35
            feedback_parts.append("Email successfully queued in Unsent Messages")
            
            # --- CRITERION 3: Correct Content (15 points) ---
            recipient = unsent_msg.get('To', '').lower()
            body = get_email_body(unsent_msg).lower()
            
            content_score = 0
            if expected_recipient.lower() in recipient:
                content_score += 5
            
            keywords_found = sum(1 for kw in expected_keywords if kw.lower() in body)
            if keywords_found == len(expected_keywords):
                content_score += 10
            elif keywords_found > 0:
                content_score += 5
                
            score += content_score
            if content_score == 15:
                feedback_parts.append("Recipient and body content match expectations")
            else:
                feedback_parts.append("Partial/incorrect recipient or body content")
                
        else:
            feedback_parts.append("Email NOT found in Unsent Messages queue")
            
        # --- CRITERION 4: Excluded from Drafts/Sent (15 points) ---
        draft_msg = search_mbox_for_subject(mbox_drafts.name, expected_subject)
        sent_msg = search_mbox_for_subject(mbox_sent.name, expected_subject)
        
        if draft_msg:
            feedback_parts.append("Email was incorrectly saved as Draft")
        elif sent_msg:
            feedback_parts.append("Email was incorrectly Sent instead of queued")
        else:
            score += 15
            feedback_parts.append("Email strictly queued (not in Drafts or Sent)")
            
    finally:
        for f in [mbox_unsent, mbox_drafts, mbox_sent]:
            if os.path.exists(f.name):
                os.unlink(f.name)

    # --- CRITERION 5: VLM Trajectory Verification (20 points) ---
    vlm_score = 0
    if VLM_AVAILABLE and 'sample_trajectory_frames' in globals():
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            vlm_result = query_vlm(images=frames, prompt=VLM_PROMPT)
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("offline_toggled"):
                    vlm_score += 10
                if parsed.get("send_later_used"):
                    vlm_score += 10
                
                score += vlm_score
                feedback_parts.append(f"VLM verified workflow: +{vlm_score} pts")
            else:
                feedback_parts.append("VLM verification failed or inconclusive")
    
    # Passing condition: Score >= 70 AND the email is strictly in the Unsent Messages queue
    is_queued = (unsent_msg is not None)
    passed = (score >= 70) and is_queued

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }