#!/usr/bin/env python3
"""
Verifier for reply_and_forward task.

Verification Logic:
1. Scan result JSON for new emails in Sent or Drafts.
2. Identify a "Reply" action:
   - Subject usually starts with "Re:"
   - References the original "razor" thread (keyword check in subject).
   - Addressed to original sender (we check if address is NOT the forward recipient).
   - Body contains "received your message".
3. Identify a "Forward" action:
   - Subject usually starts with "Fwd:" or "Fw:"
   - Addressed to 'dev-team@consultancy.com'.
   - Body contains "review".
4. VLM verification for workflow confirmation (Compose window usage).
"""

import json
import tempfile
import os
import sys
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reply_and_forward(traj, env_info, task_info):
    """Verify reply and forward task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    forward_recipient = metadata.get('forward_recipient', 'dev-team@consultancy.com').lower()
    reply_phrase = metadata.get('reply_required_phrase', 'received your message').lower()
    forward_phrase = metadata.get('forward_required_phrase', 'review').lower()
    target_keyword = metadata.get('target_keyword', 'razor').lower()

    # Load result
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

    actions = result.get('actions', [])
    
    score = 0
    feedback_parts = []
    
    # ----------------------------------------------------------------
    # Analyze Actions
    # ----------------------------------------------------------------
    
    found_reply = False
    found_forward = False
    
    # Track which specific email satisfied which requirement to avoid double counting
    reply_email_idx = -1
    forward_email_idx = -1
    
    # 1. Identify Forward (Strict recipient check)
    for i, email in enumerate(actions):
        to_field = email.get('to', '').lower()
        if forward_recipient in to_field:
            forward_email_idx = i
            found_forward = True
            score += 20 # Base points for creating the forward
            feedback_parts.append("Forward email found")
            
            # Check subject
            subject = email.get('subject', '').lower()
            if "fwd" in subject or "fw" in subject:
                # Good prefix
                pass
            if target_keyword in subject:
                score += 2.5 # Half of the 5pt subject continuity bonus
            
            # Check body
            body = email.get('body', '')
            if forward_phrase in body:
                score += 10
                feedback_parts.append(f"Forward content correct ('{forward_phrase}')")
            else:
                feedback_parts.append(f"Forward content missing phrase '{forward_phrase}'")
                
            # Correct recipient (already checked for finding it, but awarding specific points)
            score += 15 
            break
            
    # 2. Identify Reply (Remaining email, not the forward)
    for i, email in enumerate(actions):
        if i == forward_email_idx:
            continue
            
        # It's a reply if it's NOT the forward recipient
        to_field = email.get('to', '').lower()
        
        # Heuristic: If we haven't found a reply yet, and this isn't to the forward recipient
        if forward_recipient not in to_field:
            reply_email_idx = i
            found_reply = True
            score += 20 # Base points for creating the reply
            feedback_parts.append("Reply email found")
            
            # Check subject
            subject = email.get('subject', '').lower()
            if "re:" in subject:
                # Good prefix
                pass
            if target_keyword in subject:
                score += 2.5 # Other half of subject continuity bonus
            
            # Check body
            body = email.get('body', '')
            if reply_phrase in body:
                score += 10
                feedback_parts.append(f"Reply content correct ('{reply_phrase}')")
            else:
                feedback_parts.append(f"Reply content missing phrase '{reply_phrase}'")
            
            # Check recipient validity (should NOT be empty)
            if to_field and len(to_field) > 3:
                score += 15
            else:
                feedback_parts.append("Reply recipient invalid/empty")
            break

    if not found_forward:
        feedback_parts.append(f"No email sent to {forward_recipient}")
    if not found_reply:
        feedback_parts.append("No reply email found (distinct from forward)")

    # ----------------------------------------------------------------
    # VLM Verification (Workflow) - 5 points
    # ----------------------------------------------------------------
    query_vlm = env_info.get('query_vlm')
    sample_trajectory_frames = env_info.get('sample_trajectory_frames')
    
    vlm_score = 0
    if query_vlm and traj and sample_trajectory_frames:
        try:
            frames = sample_trajectory_frames(traj, num_samples=5)
            prompt = """Analyze these screenshots of an email client task.
            The user should have:
            1. Opened an email about 'razor'.
            2. Replied to it.
            3. Forwarded it.
            
            Do you see:
            - An opened email with 'Razor' in the subject or body?
            - A 'Compose' or 'Reply' window (often has 'Re:' in subject)?
            - A 'Forward' window (often has 'Fwd:' in subject)?
            
            Respond JSON: {"reply_seen": bool, "forward_seen": bool, "razor_email_seen": bool}"""
            
            vlm_res = query_vlm(images=frames, prompt=prompt)
            parsed = vlm_res.get('parsed', {}) if isinstance(vlm_res, dict) else {}
            
            if parsed.get('reply_seen') or parsed.get('forward_seen'):
                vlm_score = 5
                feedback_parts.append("VLM confirmed workflow")
        except:
            pass
    
    score += vlm_score

    return {
        "passed": score >= 70,
        "score": min(100, score),
        "feedback": "; ".join(feedback_parts)
    }