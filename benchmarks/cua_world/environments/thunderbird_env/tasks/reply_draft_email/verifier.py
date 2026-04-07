#!/usr/bin/env python3
"""
Verifier for reply_draft_email task.

Verification Strategy:
1. Copy Drafts.mbox and Sent.mbox from container.
2. Programmatic check 1: A new email exists in Drafts.
3. Programmatic check 2: The draft is addressed to Marcus Chen.
4. Programmatic check 3: The subject contains "Re:" and original subject.
5. Programmatic check 4: Body contains 6 required business logic elements.
6. Programmatic check 5: Ensure the email is NOT in the Sent folder.
7. VLM verification: Check trajectory frames to ensure the Thunderbird compose 
   window was legitimately interacted with.
"""

import os
import json
import re
import mailbox
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM utilities from the framework
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    logger.warning("VLM utilities not available, VLM verification will be skipped.")

def get_email_body(msg):
    """Extract the full text body from an email message."""
    body = ""
    if msg.is_multipart():
        for part in msg.walk():
            content_type = part.get_content_type()
            if content_type == "text/plain":
                payload = part.get_payload(decode=True)
                if payload:
                    body += payload.decode("utf-8", errors="replace")
    else:
        payload = msg.get_payload(decode=True)
        if payload:
            body = payload.decode("utf-8", errors="replace")
    return body

def verify_reply_draft(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_recipient = metadata.get('expected_recipient', 'marcus.chen@pacificrim-supply.com').lower()
    expected_phrase = metadata.get('expected_phrase', 'formal quote').lower()

    score = 0
    feedback_parts = []
    
    # -------------------------------------------------------------------------
    # 1. Fetch JSON and mbox files from container
    # -------------------------------------------------------------------------
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_drafts = tempfile.NamedTemporaryFile(delete=False, suffix='.mbox')
    tmp_sent = tempfile.NamedTemporaryFile(delete=False, suffix='.mbox')

    try:
        copy_from_env("/tmp/task_result.json", tmp_json.name)
        copy_from_env("/tmp/Drafts.mbox", tmp_drafts.name)
        copy_from_env("/tmp/Sent.mbox", tmp_sent.name)
        
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve exported files: {e}"}

    # -------------------------------------------------------------------------
    # 2. Check Drafts Mbox
    # -------------------------------------------------------------------------
    initial_drafts = result.get('initial_draft_count', 0)
    final_drafts = result.get('final_draft_count', 0)
    
    if final_drafts <= initial_drafts:
        feedback_parts.append("FAIL: No new drafts found.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback_parts)}
    else:
        score += 10
        feedback_parts.append("PASS: New draft found (+10).")

    # Parse Drafts
    drafts_box = mailbox.mbox(tmp_drafts.name)
    target_draft = None
    
    for msg in drafts_box:
        to_field = str(msg.get("To", "")).lower()
        if expected_recipient in to_field:
            target_draft = msg
            # Take the last matching one (most recent)
            
    if not target_draft:
        feedback_parts.append("FAIL: No draft found addressed to Marcus Chen.")
        return {"passed": False, "score": score, "feedback": "\n".join(feedback_parts)}
    else:
        score += 10
        feedback_parts.append("PASS: Draft addressed to correct recipient (+10).")

    # -------------------------------------------------------------------------
    # 3. Check Subject
    # -------------------------------------------------------------------------
    subject = str(target_draft.get("Subject", ""))
    if re.search(r"Re:.*Product Availability.*Industrial Fasteners", subject, re.IGNORECASE):
        score += 10
        feedback_parts.append("PASS: Subject has 'Re:' prefix and correct title (+10).")
    else:
        feedback_parts.append(f"FAIL: Incorrect subject '{subject}'. Expected reply prefix.")

    # -------------------------------------------------------------------------
    # 4. Check Body Business Logic Requirements
    # -------------------------------------------------------------------------
    body = get_email_body(target_draft)
    body_lower = body.lower()
    
    # 4a. M10 / 15,000
    if bool(re.search(r"m10", body_lower)) and bool(re.search(r"15[,.]?000", body_lower)):
        score += 10
        feedback_parts.append("PASS: Mentions M10 hex bolts and 15,000 units (+10).")
    
    # 4b. M8 / 8,500
    if bool(re.search(r"m8", body_lower)) and bool(re.search(r"8[,.]?500", body_lower)):
        score += 10
        feedback_parts.append("PASS: Mentions M8 carriage bolts and 8,500 units (+10).")
        
    # 4c. Pricing M10 ($0.42)
    if bool(re.search(r"\$?\s*0\.42", body_lower) or re.search(r"42\s*cents", body_lower)):
        score += 10
        feedback_parts.append("PASS: Includes $0.42 pricing (+10).")
        
    # 4d. Pricing M8 ($0.38)
    if bool(re.search(r"\$?\s*0\.38", body_lower) or re.search(r"38\s*cents", body_lower)):
        score += 10
        feedback_parts.append("PASS: Includes $0.38 pricing (+10).")
        
    # 4e. Discount
    if bool(re.search(r"12\s*%", body_lower) or re.search(r"12\s*percent", body_lower)):
        score += 10
        feedback_parts.append("PASS: Includes 12% discount (+10).")
        
    # 4f. Delivery
    if bool(re.search(r"5[\s\-to]+7", body_lower)):
        score += 5
        feedback_parts.append("PASS: Includes 5-7 delivery timeline (+5).")
        
    # 4g. Expected phrase
    if expected_phrase in body_lower:
        score += 5
        feedback_parts.append("PASS: Includes required phrase about formal quote (+5).")

    # -------------------------------------------------------------------------
    # 5. Check Negative Constraint: Was NOT Sent
    # -------------------------------------------------------------------------
    sent_box = mailbox.mbox(tmp_sent.name)
    was_sent = False
    for msg in sent_box:
        if expected_recipient in str(msg.get("To", "")).lower():
            was_sent = True
            break
            
    if was_sent:
        score -= 20
        feedback_parts.append("CRITICAL FAIL: Email was sent! It must be saved as a draft. (-20)")
    else:
        score += 10
        feedback_parts.append("PASS: Email correctly not found in Sent folder (+10).")

    # -------------------------------------------------------------------------
    # 6. VLM Trajectory Verification
    # -------------------------------------------------------------------------
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        all_images = frames + [final_img] if final_img else frames
        
        prompt = """Look at this sequence of screenshots from a user interacting with Thunderbird email.
        Did the user open a 'Write' or 'Compose' window (or reply to an email) and type a message? 
        Respond in JSON: {"compose_window_visible": true/false, "typing_occurred": true/false}"""
        
        vlm_res = query_vlm(images=all_images, prompt=prompt)
        if vlm_res and vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("compose_window_visible") and parsed.get("typing_occurred"):
                score += 0 # Used strictly as anti-gaming validation, programmatic is primary score
                feedback_parts.append("PASS: VLM verified trajectory shows compose/reply workflow.")
            else:
                score -= 30
                feedback_parts.append("FAIL: VLM did not observe the compose workflow in trajectory frames. (-30)")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")

    # -------------------------------------------------------------------------
    # Final Result Compilation
    # -------------------------------------------------------------------------
    # Clean up temp files
    for tmp_file in [tmp_json, tmp_drafts, tmp_sent]:
        if os.path.exists(tmp_file.name):
            os.unlink(tmp_file.name)

    # Threshold for passing is 80 (indicates majority of data was included and constraints met)
    passed = score >= 80 and not was_sent
    
    return {
        "passed": passed,
        "score": max(0, min(100, score)),
        "feedback": "\n".join(feedback_parts)
    }