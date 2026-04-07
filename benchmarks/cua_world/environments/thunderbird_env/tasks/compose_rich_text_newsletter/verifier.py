#!/usr/bin/env python3
"""
Verifier for compose_rich_text_newsletter task.
Programmatically inspects the Drafts mbox file to verify HTML composition
structure, embedded image paths, and table row generation.
"""

import json
import os
import tempfile
import mailbox
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compose_rich_text_newsletter(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}
        
    # Get metadata
    metadata = task_info.get('metadata', {})
    expected_subject = metadata.get('expected_subject', 'Q3 Townhall Update')
    expected_recipient = metadata.get('expected_recipient', 'staff@corp.example.com')
    
    # Read timing & verification result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    task_start = result.get('task_start', 0)
    drafts_mtime = result.get('drafts_mtime', 0)
    
    # ANTI-GAMING: Make sure they actually did something during the current task window
    if drafts_mtime < task_start:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Drafts folder was not modified during the task."
        }
        
    # Process Drafts mbox file
    temp_mbox = tempfile.NamedTemporaryFile(delete=False, suffix='.mbox')
    try:
        copy_from_env("/tmp/Drafts.mbox", temp_mbox.name)
        mbox = mailbox.mbox(temp_mbox.name)
        
        target_draft = None
        for msg in mbox:
            subject = str(msg.get('Subject', '')).strip()
            if expected_subject.lower() in subject.lower():
                target_draft = msg
                
        if not target_draft:
            return {"passed": False, "score": 0, "feedback": f"Draft with subject '{expected_subject}' not found."}
            
        score = 20
        feedback_parts = ["Draft found"]
        
        # Recipient Evaluation
        to_addr = str(target_draft.get('To', '')).lower()
        if expected_recipient in to_addr:
            score += 10
            feedback_parts.append("Correct recipient")
        else:
            feedback_parts.append(f"Incorrect recipient: {to_addr}")
            
        # Parse payload for Rich-Text contents
        html_content = ""
        has_image_part = False
        
        if target_draft.is_multipart():
            for part in target_draft.walk():
                ctype = part.get_content_type()
                if ctype == 'text/html':
                    payload = part.get_payload(decode=True)
                    if payload:
                        html_content += payload.decode('utf-8', errors='ignore')
                elif ctype.startswith('image/'):
                    has_image_part = True
        else:
            ctype = target_draft.get_content_type()
            if ctype == 'text/html':
                payload = target_draft.get_payload(decode=True)
                if payload:
                    html_content += payload.decode('utf-8', errors='ignore')
                    
        # Verification criteria check
        if html_content:
            score += 20
            feedback_parts.append("HTML format verified")
            
            # Inline Image Check (Could be multipart cid:, data:, or attached relation)
            has_img_tag = "<img" in html_content.lower()
            if has_img_tag and (has_image_part or "data:image" in html_content.lower() or "cid:" in html_content.lower()):
                score += 20
                feedback_parts.append("Inline image successfully embedded")
            elif has_img_tag:
                score += 10
                feedback_parts.append("Image tag found, but missing image data (attachment structure broken)")
            else:
                feedback_parts.append("No image tag found")
                
            # HTML Table Extraction
            has_table = "<table" in html_content.lower()
            if has_table:
                # Count rows regardless of table formatting tags
                tr_count = len(re.findall(r'<tr\b[^>]*>', html_content, re.IGNORECASE))
                if tr_count >= 3:
                    score += 30
                    feedback_parts.append(f"Table constructed with {tr_count} rows")
                else:
                    score += 15
                    feedback_parts.append(f"Table found with only {tr_count} rows (expected >= 3)")
            else:
                feedback_parts.append("No table found")
        else:
            feedback_parts.append("Email is strictly plaintext, not HTML format")
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error parsing mbox: {e}"}
    finally:
        if os.path.exists(temp_mbox.name):
            os.unlink(temp_mbox.name)
            
    passed = score >= 70
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback_parts)}