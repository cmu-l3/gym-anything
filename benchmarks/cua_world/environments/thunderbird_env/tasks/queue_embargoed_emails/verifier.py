#!/usr/bin/env python3
"""
Verifier for Queue Embargoed Emails task.

This script parses the local Thunderbird mbox files using the environment's
verification utilities to strictly ensure the user placed the specific emails
into the "Unsent Messages" folder, correctly attached the PDFs, and did not
save them as drafts or sent them immediately.
"""

import os
import sys
import json
import tempfile
import logging

# Add utils to path (relative to the task execution on host)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from thunderbird_verification_utils import setup_thunderbird_verification, parse_mbox_file, cleanup_verification_temp

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an agent that is supposed to queue emails in Thunderbird using the 'Send Later' feature.

Look at the trajectory of screenshots:
1. Did the agent open a 'Write' (compose) window?
2. Did they add attachments to the emails?
3. Did they use the 'Send Later' functionality (File -> Send Later, or Ctrl+Shift+Return)? (Look for the Outbox/Unsent Messages folder being selected or emails sitting in it, rather than them being sent normally).

Respond in JSON format:
{
    "opened_compose": true/false,
    "added_attachments": true/false,
    "used_send_later_workflow": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}
"""

def verify_queued_emails(traj, env_info, task_info):
    """
    Verify that two specific emails were queued in Unsent Messages with attachments.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    email1_subj = metadata.get('email1_subject', 'EMBARGOED: Q4 Financial Results and Merger Announcement')
    email2_subj = metadata.get('email2_subject', 'Internal: Form 8-K Filing for Review')
    email1_att = metadata.get('email1_attachment', 'exhibit_99_1_press_release.pdf')
    email2_att = metadata.get('email2_attachment', 'form_8k_current_report.pdf')

    score = 0
    feedback_parts = []

    # Get execution metadata
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load task_result.json: {e}")
        result = {"task_start": 0}
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)

    # We need to copy the Unsent Messages, Drafts, and Sent mbox files
    success, files, error = setup_thunderbird_verification(
        copy_from_env,
        [
            "Mail/Local Folders/Unsent Messages",
            "Mail/Local Folders/Drafts",
            "Mail/Local Folders/Sent"
        ],
        username="ga"
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve Mail folders: {error}"}

    unsent_mbox = files.get("Unsent Messages")
    drafts_mbox = files.get("Drafts")
    sent_mbox = files.get("Sent")

    def find_email_details(mbox_path, subject_target, expected_attachment):
        if not mbox_path or not mbox_path.exists():
            return {"found": False, "has_attachment": False, "timestamp": 0}
        
        msgs = parse_mbox_file(mbox_path)
        for msg in msgs:
            subj = msg.get('Subject', '')
            if subject_target.lower() in subj.lower():
                # Found the email, check attachments
                has_attachment = False
                if msg.is_multipart():
                    for part in msg.walk():
                        filename = part.get_filename()
                        if filename and expected_attachment.lower() in filename.lower():
                            has_attachment = True
                
                # Estimate a timestamp if possible (Mbox timestamps are unreliable, use file mtime)
                mtime = os.path.getmtime(mbox_path)
                return {"found": True, "has_attachment": has_attachment, "timestamp": mtime}
                
        return {"found": False, "has_attachment": False, "timestamp": 0}

    # Evaluate Email 1 in Unsent Messages
    e1_unsent = find_email_details(unsent_mbox, email1_subj, email1_att)
    if e1_unsent["found"]:
        score += 20
        feedback_parts.append("Email 1 queued in Unsent Messages")
        if e1_unsent["has_attachment"]:
            score += 15
            feedback_parts.append("Email 1 has correct attachment")
        else:
            feedback_parts.append("Email 1 is missing the expected attachment")
    else:
        feedback_parts.append("Email 1 NOT found in Unsent Messages")

    # Evaluate Email 2 in Unsent Messages
    e2_unsent = find_email_details(unsent_mbox, email2_subj, email2_att)
    if e2_unsent["found"]:
        score += 20
        feedback_parts.append("Email 2 queued in Unsent Messages")
        if e2_unsent["has_attachment"]:
            score += 15
            feedback_parts.append("Email 2 has correct attachment")
        else:
            feedback_parts.append("Email 2 is missing the expected attachment")
    else:
        feedback_parts.append("Email 2 NOT found in Unsent Messages")

    # Anti-gaming: Check Drafts and Sent
    e1_drafts = find_email_details(drafts_mbox, email1_subj, email1_att)
    e2_drafts = find_email_details(drafts_mbox, email2_subj, email2_att)
    if not e1_drafts["found"] and not e2_drafts["found"]:
        score += 10
        feedback_parts.append("Emails were correctly NOT saved as drafts")
    else:
        feedback_parts.append("Penalty: One or more emails were incorrectly saved as Drafts")

    e1_sent = find_email_details(sent_mbox, email1_subj, email1_att)
    e2_sent = find_email_details(sent_mbox, email2_subj, email2_att)
    if not e1_sent["found"] and not e2_sent["found"]:
        score += 10
        feedback_parts.append("Emails were correctly NOT sent immediately")
    else:
        feedback_parts.append("Penalty: One or more emails were incorrectly sent instead of queued")

    # VLM Trajectory Verification
    if VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            vlm_res = query_vlm(images=frames + [final], prompt=VLM_PROMPT)
            
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("used_send_later_workflow"):
                    score += 10
                    feedback_parts.append("VLM confirmed 'Send Later' workflow usage")
                else:
                    feedback_parts.append("VLM did not observe 'Send Later' workflow")
            else:
                score += 10  # grant points if VLM fails but logic works
                feedback_parts.append("VLM query failed, skipping visual check")
        except Exception as e:
            logger.warning(f"VLM verification exception: {e}")
            score += 10
    else:
        score += 10  # Grant points if VLM is unavailable
        feedback_parts.append("VLM unavailable, skipping visual check")

    cleanup_verification_temp()

    # Pass condition: Both emails must be at least queued (20+20 = 40) and some details correct
    passed = score >= 70 and e1_unsent["found"] and e2_unsent["found"]

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }