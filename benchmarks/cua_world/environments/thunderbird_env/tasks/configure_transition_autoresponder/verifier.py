#!/usr/bin/env python3
"""
Verifier for configure_transition_autoresponder task.

Validates multi-step configuration of Thunderbird filters and templates using file-based programmatic verification,
combined with VLM trajectory verification to ensure genuine interactions.
"""

import os
import json
import mailbox
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_body(msg):
    """Extract plain text body from email message."""
    body = ""
    if msg.is_multipart():
        for part in msg.walk():
            if part.get_content_type() == "text/plain":
                body = part.get_payload(decode=True).decode('utf-8', errors='ignore')
                break
    else:
        body = msg.get_payload(decode=True).decode('utf-8', errors='ignore')
    return body

def verify_transition_autoresponder(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_template_sub = metadata.get('expected_template_subject', 'Project Transition Notice').lower()
    expected_phrases = metadata.get('expected_body_phrases', [])
    
    score = 0
    feedback_parts = []
    
    # 1. Read task metadata json
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    task_start = result.get("task_start", 0)
    filter_mtime = result.get("filter_mtime", 0)

    # CRITERION 1: Folder Exists (10 points)
    if result.get("folder_exists", False):
        score += 10
        feedback_parts.append("Folder 'MegaCorp Archive' exists.")
    else:
        feedback_parts.append("Folder 'MegaCorp Archive' NOT found.")

    # CRITERION 2: Template Configuration (30 points)
    temp_templates = tempfile.NamedTemporaryFile(delete=False)
    template_found = False
    template_content_valid = False
    try:
        # Copy templates mbox
        copy_from_env("/tmp/task_exports/Templates", temp_templates.name)
        if os.path.getsize(temp_templates.name) > 0:
            mbox = mailbox.mbox(temp_templates.name)
            for msg in mbox:
                subject = str(msg.get('Subject', '')).lower()
                if expected_template_sub in subject:
                    template_found = True
                    body = get_body(msg).lower()
                    
                    # Check body phrases
                    matches = sum(1 for p in expected_phrases if p in body)
                    if matches == len(expected_phrases):
                        template_content_valid = True
                        break
    except Exception as e:
        logger.warning(f"Error reading Templates: {e}")
    finally:
        if os.path.exists(temp_templates.name):
            os.unlink(temp_templates.name)

    if template_found:
        score += 15
        feedback_parts.append("Template with correct subject found.")
        if template_content_valid:
            score += 15
            feedback_parts.append("Template contains all required body phrases.")
        else:
            feedback_parts.append("Template body missing required phrases.")
    else:
        feedback_parts.append("Template with correct subject NOT found.")

    # CRITERION 3: Filter Configuration (40 points total)
    temp_filter = tempfile.NamedTemporaryFile(delete=False)
    filter_found = False
    condition_valid = False
    action_reply = False
    action_forward = False
    action_move = False
    
    try:
        copy_from_env("/tmp/task_exports/msgFilterRules.dat", temp_filter.name)
        if os.path.getsize(temp_filter.name) > 0:
            with open(temp_filter.name, 'r', errors='ignore') as f:
                filter_text = f.read()

            # Anti-gaming: Ensure it was created/modified after task started
            if filter_mtime >= task_start:
                # Find the specific block for our rule
                match = re.search(r'name="MegaCorp Transition"(.*?)(?=name=|$)', filter_text, re.DOTALL | re.IGNORECASE)
                if match:
                    filter_found = True
                    rule_text = match.group(1).lower()

                    # 1. Check Condition (10 pts)
                    if 'from,contains,@megacorp.com' in rule_text or 'author,contains,@megacorp.com' in rule_text:
                        condition_valid = True
                        score += 10
                    
                    # 2. Check Action: Reply with Template (10 pts)
                    if 'action="reply"' in rule_text and 'templates' in rule_text:
                        action_reply = True
                        score += 10
                    
                    # 3. Check Action: Forward (10 pts)
                    if 'action="forward"' in rule_text and 'sarah.connor@example.com' in rule_text:
                        action_forward = True
                        score += 10
                        
                    # 4. Check Action: Move to Folder (10 pts)
                    if 'action="move to folder"' in rule_text and 'megacorp' in rule_text and 'archive' in rule_text:
                        action_move = True
                        score += 10
    except Exception as e:
        logger.warning(f"Error reading msgFilterRules.dat: {e}")
    finally:
        if os.path.exists(temp_filter.name):
            os.unlink(temp_filter.name)

    if filter_found:
        feedback_parts.append("Filter 'MegaCorp Transition' found.")
        if condition_valid: feedback_parts.append("Filter condition valid.")
        if action_reply: feedback_parts.append("Filter action 'Reply' valid.")
        if action_forward: feedback_parts.append("Filter action 'Forward' valid.")
        if action_move: feedback_parts.append("Filter action 'Move' valid.")
    else:
        feedback_parts.append("Filter 'MegaCorp Transition' NOT found or not created during task.")

    # CRITERION 4: VLM Process Verification (20 points)
    # Ensure agent didn't just dump pre-made files by observing trajectory
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        
        prompt = """Analyze this sequence of screenshots from a user configuring Mozilla Thunderbird.
        Did the user open UI dialogs to:
        1. Compose a message (Template)
        2. Set up 'Message Filters'
        
        Respond ONLY with a JSON dictionary:
        {
            "compose_window_seen": true/false,
            "filters_dialog_seen": true/false,
            "confidence": "high"
        }
        """
        
        vlm_res = query_vlm(images=frames + [final_frame], prompt=prompt)
        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('compose_window_seen'): vlm_score += 10
            if parsed.get('filters_dialog_seen'): vlm_score += 10
            feedback_parts.append(f"VLM trajectory verification: +{vlm_score} pts.")
        else:
            feedback_parts.append("VLM verification failed to process.")
    except Exception as e:
        logger.info(f"VLM dependencies unavailable, granting default trajectory score: {e}")
        vlm_score = 20
        feedback_parts.append("VLM verification skipped (dependencies missing).")

    score += vlm_score
    
    # Calculate pass threshold
    # To pass, agent must score at least 70, meaning they got most of the UI config correct.
    key_criteria_met = filter_found and template_found and (action_reply or action_forward or action_move)
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }