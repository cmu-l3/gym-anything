#!/usr/bin/env python3
"""
Verifier for create_email_template task.

HYBRID MULTI-SIGNAL VERIFICATION:
1. Anti-gaming check: Templates file modified after task start (15 points)
2. Content check: Subject matches exactly (15 points)
3. Content check: Body contains all required keywords/phrases (20 points)
4. Negative check: Message was not saved to Drafts or Sent (10 points)
5. VLM check: Trajectory frames confirm compose window was used and template saved (40 points)
"""

import os
import json
import logging
import tempfile
import mailbox
from email.header import decode_header
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an AI agent's performance on a Thunderbird email client task.
The user's goal was to create a new email template (NOT a draft, and NOT sent).

Look at the provided sequence of screenshots from the agent's trajectory (chronological order).
Assess the agent's workflow by answering these questions:

1. Did the agent open an email compose window at any point?
2. Did the agent type a message referencing a "Product Demo" and "Next Steps"?
3. Did the agent navigate to save the message specifically as a Template (e.g., clicking File -> Save As -> Template)?
4. Did the agent accidentally send the email or explicitly click "Save" (which defaults to Draft) instead of Template?

Respond in JSON format:
{
    "opened_compose_window": true/false,
    "typed_correct_content": true/false,
    "saved_as_template": true/false,
    "saved_as_draft_instead": true/false,
    "sent_instead": true/false,
    "confidence": "high/medium/low",
    "reasoning": "brief explanation of the visual evidence"
}
"""

def decode_subject(subject_raw):
    if not subject_raw:
        return ""
    decoded_parts = decode_header(subject_raw)
    result = []
    for part, charset in decoded_parts:
        if isinstance(part, bytes):
            result.append(part.decode(charset or 'utf-8', errors='replace'))
        else:
            result.append(str(part))
    return " ".join(result)

def get_body_text(msg):
    body = ""
    if msg.is_multipart():
        for part in msg.walk():
            ctype = part.get_content_type()
            if ctype == "text/plain":
                payload = part.get_payload(decode=True)
                if payload:
                    body += payload.decode(part.get_content_charset() or 'utf-8', errors='replace')
    else:
        payload = msg.get_payload(decode=True)
        if payload:
            body = payload.decode(msg.get_content_charset() or 'utf-8', errors='replace')
    return body

def check_mbox_for_subject(mbox_path, target_subject):
    """Returns True if the mbox file contains an email with the target subject."""
    if not os.path.exists(mbox_path) or os.path.getsize(mbox_path) == 0:
        return False
    try:
        mbox = mailbox.mbox(mbox_path)
        for msg in mbox:
            subject = decode_subject(msg.get('Subject', '')).lower()
            if target_subject.lower() in subject:
                return True
    except Exception as e:
        logger.warning(f"Error reading mbox {mbox_path}: {e}")
    return False

def verify_email_template(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_subject = metadata.get('expected_subject', 'Follow-Up: Product Demo and Next Steps')
    expected_phrases = metadata.get('expected_phrases', [])

    score = 0
    feedback_parts = []

    # 1. Fetch JSON result and MBOX files from the environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_templates = tempfile.NamedTemporaryFile(delete=False, suffix='.mbox')
    temp_drafts = tempfile.NamedTemporaryFile(delete=False, suffix='.mbox')
    temp_sent = tempfile.NamedTemporaryFile(delete=False, suffix='.mbox')
    
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
            
        copy_from_env("/tmp/tb_templates.mbox", temp_templates.name)
        copy_from_env("/tmp/tb_drafts.mbox", temp_drafts.name)
        copy_from_env("/tmp/tb_sent.mbox", temp_sent.name)
        
        # Criterion 1: Anti-gaming (Modified during task)
        modified_during_task = result.get('modified_during_task', False)
        if modified_during_task:
            score += 15
            feedback_parts.append("Templates file successfully modified during task.")
        else:
            feedback_parts.append("Templates file was not modified or is empty.")

        # Parse Templates mbox
        template_subject_match = False
        template_body_score = 0
        
        if os.path.getsize(temp_templates.name) > 0:
            mbox = mailbox.mbox(temp_templates.name)
            if len(mbox) > 0:
                # Assuming the last message is the newly created template
                msg = mbox[len(mbox) - 1]
                
                # Criterion 2: Subject check
                actual_subject = decode_subject(msg.get('Subject', ''))
                if expected_subject.lower() in actual_subject.lower():
                    score += 15
                    template_subject_match = True
                    feedback_parts.append("Subject matches expected value.")
                else:
                    feedback_parts.append(f"Subject mismatch: '{actual_subject}'.")
                    
                # Criterion 3: Body phrases check
                body_text = get_body_text(msg).lower()
                phrases_found = sum(1 for p in expected_phrases if p.lower() in body_text)
                
                if len(expected_phrases) > 0:
                    phrase_ratio = phrases_found / len(expected_phrases)
                    awarded_body_pts = int(20 * phrase_ratio)
                    score += awarded_body_pts
                    feedback_parts.append(f"Found {phrases_found}/{len(expected_phrases)} expected body phrases (+{awarded_body_pts} pts).")
            else:
                feedback_parts.append("No valid messages found inside Templates mbox.")

        # Criterion 4: Negative check (Not in Drafts/Sent)
        in_drafts = check_mbox_for_subject(temp_drafts.name, expected_subject)
        in_sent = check_mbox_for_subject(temp_sent.name, expected_subject)
        
        if not in_drafts and not in_sent:
            score += 10
            feedback_parts.append("Verified message was NOT erroneously saved to Drafts or Sent.")
        else:
            feedback_parts.append("Message was found in Drafts or Sent folder (Incorrect save mechanism used).")

    except Exception as e:
        logger.error(f"Error during file processing: {e}")
        feedback_parts.append(f"Error processing files: {e}")
    finally:
        for tmp_file in [temp_result, temp_templates, temp_drafts, temp_sent]:
            if os.path.exists(tmp_file.name):
                os.unlink(tmp_file.name)

    # Criterion 5: VLM Trajectory Verification
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        vlm_res = query_vlm(images=frames, prompt=VLM_PROMPT)
        if vlm_res and vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            
            if parsed.get("opened_compose_window"):
                vlm_score += 10
            if parsed.get("typed_correct_content"):
                vlm_score += 10
            if parsed.get("saved_as_template") and not parsed.get("saved_as_draft_instead") and not parsed.get("sent_instead"):
                vlm_score += 20
                
            confidence_multiplier = {"high": 1.0, "medium": 0.8, "low": 0.5}.get(parsed.get("confidence", "low"), 0.5)
            vlm_score = int(vlm_score * confidence_multiplier)
            score += vlm_score
            feedback_parts.append(f"VLM visual verification awarded {vlm_score}/40 points. (Reasoning: {parsed.get('reasoning', 'None')})")
        else:
            feedback_parts.append("VLM query failed or returned no data.")
    except Exception as e:
        logger.error(f"VLM Exception: {e}")
        feedback_parts.append("VLM verification encountered an error.")

    # Final Evaluation
    key_criteria_met = modified_during_task and template_subject_match
    passed = (score >= 60) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }