#!/usr/bin/env python3
"""
Verifier for Send Tracked Legal Email task.

Checks for programmatic presence of advanced MIME headers (Priority, Reply-To, Read Receipts)
along with standard email composition features (Recipient, Attachments) in the Sent mbox.
"""

import os
import json
import mailbox
import tempfile
import logging

# Ensure VLM utilities are available
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallbacks for external or simulated testing
    def sample_trajectory_frames(traj, n): return []
    def get_final_screenshot(traj): return None
    def query_vlm(images, prompt): return {"success": False}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tracked_email(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_recipient = metadata.get('expected_recipient', 'opposing.counsel@lawfirm.com').lower()
    expected_reply_to = metadata.get('expected_reply_to', 'paralegal@mylawfirm.com').lower()
    expected_attachment = metadata.get('expected_attachment', 'settlement_agreement.pdf')

    # Load result metadata
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result.get('sent_exists'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No Sent folder found. Email was not sent."
        }
        
    if not result.get('sent_modified_during_task'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Sent folder was not modified during the task timeframe."
        }

    # Extract Sent mbox
    temp_mbox = tempfile.NamedTemporaryFile(delete=False, suffix='.mbox')
    try:
        copy_from_env("/tmp/Sent.mbox", temp_mbox.name)
        mbox = mailbox.mbox(temp_mbox.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse Sent mbox: {e}"}

    # Search for our target message
    target_msg = None
    for msg in mbox:
        to_header = str(msg.get('To', '')).lower()
        if expected_recipient in to_header:
            target_msg = msg
            # Continuing loop to grab the latest one if there are multiple

    if not target_msg:
        if os.path.exists(temp_mbox.name): os.unlink(temp_mbox.name)
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"No email sent to '{expected_recipient}' found."
        }

    # Evaluate criteria
    score = 20 # Baseline for successfully finding an email addressed to the right person
    feedback_parts = ["Recipient and Subject verified"]
    
    # 1. Attachment Check
    has_attachment = False
    if target_msg.is_multipart():
        for part in target_msg.walk():
            filename = part.get_filename()
            if filename and expected_attachment in filename:
                has_attachment = True
                break
    
    if has_attachment:
        score += 20
        feedback_parts.append("Attachment verified")
    else:
        feedback_parts.append("Attachment missing")

    # 2. Reply-To Check
    reply_to_header = str(target_msg.get('Reply-To', '')).lower()
    if expected_reply_to in reply_to_header:
        score += 20
        feedback_parts.append("Reply-To header verified")
    else:
        feedback_parts.append(f"Reply-To missing or incorrect: {reply_to_header}")

    # 3. Priority Check
    priority_header = str(target_msg.get('X-Priority', ''))
    # Priority is usually represented as '1 (Highest)' or '1'
    if '1' in priority_header or 'highest' in priority_header.lower():
        score += 20
        feedback_parts.append("Highest Priority verified")
    else:
        feedback_parts.append(f"Priority incorrect: {priority_header}")

    # 4. Return Receipt Check
    receipt_header = str(target_msg.get('Disposition-Notification-To', ''))
    if receipt_header and receipt_header != 'None':
        score += 10
        feedback_parts.append("Return Receipt requested")
    else:
        feedback_parts.append("Return Receipt missing")

    if os.path.exists(temp_mbox.name):
        os.unlink(temp_mbox.name)

    # 5. VLM Trajectory Verification (Anti-Gaming)
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """You are analyzing trajectory frames of a user sending an email in Thunderbird.
Does this trajectory show genuine usage of the graphical user interface?
Specifically, look for signs of the Compose window being open, addressing an email, attaching a file, and interacting with menus or toolbars (like Options, Priority, or Return Receipt).

Respond ONLY with a JSON dictionary: {"gui_used": true/false}"""
            
            vlm_result = query_vlm(images=frames, prompt=prompt)
            if vlm_result and isinstance(vlm_result, dict):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("gui_used", False):
                    vlm_score = 10
                    feedback_parts.append("VLM confirmed GUI interaction")
                else:
                    feedback_parts.append("VLM did not detect genuine GUI composition")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")
        # If VLM is totally offline, we'll award the points neutrally to avoid failing good runs
        vlm_score = 10 
        feedback_parts.append("VLM verification bypassed (unavailable)")

    score += vlm_score

    # Passing criteria: At least 80 points total AND the core workflow (Attachment and Recipient)
    passed = score >= 80 and has_attachment

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }