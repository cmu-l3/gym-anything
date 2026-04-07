#!/usr/bin/env python3
"""
Verifier for forward_emails_as_attachments task.

Multi-Criteria Verification:
1. Anti-gaming: Drafts.mbox must be modified during the task.
2. Draft Existence: A draft addressed to accounting@example-firm.com exists.
3. Message Structure: The draft is a multipart message (capable of holding attachments).
4. Attachment Integrity: Contains exactly the requested 3 emails attached as message/rfc822.
5. VLM Verification: Agent trajectory proves multi-selection and interaction in Thunderbird.
6. Negative Check: The email wasn't erroneously sent (missing from Sent.mbox).
"""

import os
import json
import tempfile
import mailbox
import email
from email.header import decode_header
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try importing VLM tools (available in gym-anything environments)
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("VLM tools not available.")

def decode_str(s):
    """Safely decode an email header string."""
    if not s:
        return ""
    decoded_list = decode_header(s)
    res = ""
    for text, charset in decoded_list:
        if isinstance(text, bytes):
            res += text.decode(charset or 'utf-8', errors='replace')
        else:
            res += text
    return res

def check_vlm_trajectory(traj):
    """Uses VLM to verify the workflow from trajectory frames."""
    if not VLM_AVAILABLE or not traj:
        return 0, "VLM tools not available or no trajectory."
    
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
        return 0, "No trajectory frames found."
        
    prompt = """You are analyzing a sequence of screenshots from an agent interacting with Mozilla Thunderbird.
    
    The task was to select MULTIPLE specific invoice emails from the inbox and forward them as ATTACHMENTS.
    
    Look at the frames and determine:
    1. Did the agent navigate the Inbox?
    2. Did the agent select multiple emails simultaneously?
    3. Did the agent open a Compose/Write window?
    4. Does the compose window show the emails added in the attachments pane rather than pasted inline as text?
    
    Respond in JSON format:
    {
        "navigated_inbox": true/false,
        "selected_multiple_emails": true/false,
        "compose_window_opened": true/false,
        "attachments_visible": true/false,
        "confidence": "high/medium/low",
        "reasoning": "Brief explanation"
    }
    """
    
    try:
        result = query_vlm(images=frames, prompt=prompt)
        if result and result.get("success"):
            parsed = result.get("parsed", {})
            score = 0
            if parsed.get("navigated_inbox"): score += 5
            if parsed.get("selected_multiple_emails"): score += 5
            if parsed.get("compose_window_opened"): score += 5
            if parsed.get("attachments_visible"): score += 10
            return score, parsed.get("reasoning", "")
    except Exception as e:
        logger.error(f"VLM query failed: {e}")
        
    return 0, "VLM evaluation failed."

def verify_forward_emails_as_attachments(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_recipient = metadata.get('expected_recipient', 'accounting@example-firm.com')
    expected_subject = metadata.get('expected_subject', 'March Invoices')
    keywords = metadata.get('keywords', ['TS-9921', 'Cloud Hosting', 'Catering'])

    # Temporary files for reading the data from the container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_drafts = tempfile.NamedTemporaryFile(delete=False, suffix='.mbox')
    temp_sent = tempfile.NamedTemporaryFile(delete=False, suffix='.mbox')
    
    score = 0
    feedback = []

    try:
        # Copy files from environment
        copy_from_env("/tmp/task_result.json", temp_json.name)
        copy_from_env("/tmp/Drafts.mbox", temp_drafts.name)
        copy_from_env("/tmp/Sent.mbox", temp_sent.name)
        
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)

        # 1. Anti-gaming: Check if drafts were modified during the task
        if result_data.get('drafts_modified_during_task', False):
            score += 10
            feedback.append("Drafts modified during task window.")
        else:
            feedback.append("Warning: Drafts file timestamp precedes task start.")
            
        # 2. Check if the message was sent (it shouldn't be)
        sent_mistake = False
        if os.path.exists(temp_sent.name) and os.path.getsize(temp_sent.name) > 0:
            sent_mbox = mailbox.mbox(temp_sent.name)
            for msg in sent_mbox:
                to_addr = decode_str(msg.get('To', '')).lower()
                if expected_recipient in to_addr:
                    sent_mistake = True
                    break
        
        if sent_mistake:
            feedback.append("FAILURE: Email was sent instead of saved as a draft.")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

        # 3. Analyze Drafts
        draft_found = False
        target_msg = None
        
        if os.path.exists(temp_drafts.name) and os.path.getsize(temp_drafts.name) > 0:
            drafts_mbox = mailbox.mbox(temp_drafts.name)
            for msg in reversed(drafts_mbox): # Look at newest first
                to_addr = decode_str(msg.get('To', '')).lower()
                subj = decode_str(msg.get('Subject', '')).lower()
                
                if expected_recipient in to_addr:
                    draft_found = True
                    target_msg = msg
                    if expected_subject.lower() in subj:
                        score += 10
                        feedback.append("Draft found with correct recipient and subject.")
                    else:
                        score += 5
                        feedback.append(f"Draft found with correct recipient but wrong subject: '{subj}'.")
                    break

        if not draft_found:
            feedback.append("FAILURE: No draft addressed to accounting@example-firm.com found.")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

        # 4. Analyze Attachments (MIME format)
        attached_invoices_found = []
        is_inline_forward = False

        if target_msg.is_multipart():
            score += 10
            feedback.append("Draft is properly formatted as a multipart message.")
            
            for part in target_msg.walk():
                content_type = part.get_content_type()
                
                # Check for rfc822 (standard email attachment)
                if content_type == 'message/rfc822':
                    payload = part.get_payload()
                    if isinstance(payload, list) and len(payload) > 0:
                        attached_email = payload[0]
                        attached_subj = decode_str(attached_email.get('Subject', ''))
                        
                        for kw in keywords:
                            if kw.lower() in attached_subj.lower() and kw not in attached_invoices_found:
                                attached_invoices_found.append(kw)
                                score += 15 # Up to 45 points for the 3 attachments
                                
                # Fallback for octet-stream/eml files if Thunderbird packaged it differently
                elif part.get_filename() and part.get_filename().endswith('.eml'):
                    filename = decode_str(part.get_filename())
                    for kw in keywords:
                        if kw.lower() in filename.lower() and kw not in attached_invoices_found:
                            attached_invoices_found.append(kw)
                            score += 15
        else:
            is_inline_forward = True
            
        # Check text body for signs of inline forwarding instead of attachments
        body_text = ""
        for part in target_msg.walk():
            if part.get_content_type() == 'text/plain':
                body_text += part.get_payload(decode=True).decode('utf-8', errors='ignore')
                
        for kw in keywords:
            if kw.lower() in body_text.lower():
                is_inline_forward = True
                
        if is_inline_forward and len(attached_invoices_found) == 0:
            feedback.append("FAILURE: Invoices were forwarded inline (text) rather than as attached files.")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback)}
            
        feedback.append(f"Successfully attached {len(attached_invoices_found)}/3 required invoice emails.")

        # 5. VLM Trajectory Verification
        vlm_score, vlm_reasoning = check_vlm_trajectory(traj)
        score += vlm_score
        if vlm_reasoning:
            feedback.append(f"VLM observation: {vlm_reasoning}")

        # Final determination
        key_criteria_met = draft_found and len(attached_invoices_found) == 3
        passed = score >= 75 and key_criteria_met

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback)
        }

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification encountered an error: {e}"}
        
    finally:
        # Cleanup temp files
        for temp_f in [temp_json, temp_drafts, temp_sent]:
            if os.path.exists(temp_f.name):
                try:
                    os.unlink(temp_f.name)
                except:
                    pass