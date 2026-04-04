#!/usr/bin/env python3
"""
Verifier for mailing_list_triage task.

Occupation context: IT Team Lead / DevOps Manager
Context: Organizing a disorganized inbox full of mailing list traffic

Scoring (100 points total, pass threshold: 65):
- 25 pts: 2+ custom IMAP folders created in Maildir
- 25 pts: Inbox reduced to fewer than 35 emails (15+ moved from baseline of 50)
- 15 pts: Custom folders collectively contain 15+ emails
- 25 pts: Draft or sent email addressed to devops-team@techcorp.org
- 10 pts: Draft/sent email subject contains 'triage', 'inbox', 'mailing', 'organize', or 'list'

Output-existence gate: if no custom folders AND no drafts/sent -> score=0
Pass threshold: 70 (requires at least partial email composition in addition to organizing)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_mailing_list_triage(traj, env_info, task_info):
    """Verify mailing list triage task completion."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    summary_recipient = metadata.get('summary_recipient', 'devops-team@techcorp.org').lower()
    initial_inbox = metadata.get('initial_inbox_count', 50)
    min_folders = metadata.get('min_folders_required', 2)
    min_moved = metadata.get('min_emails_moved', 15)

    # Copy result file from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    subscores = {}

    custom_folders = result.get('custom_folders', {})
    custom_folder_count = result.get('custom_folder_count', 0)
    inbox_count = result.get('inbox_count', initial_inbox)
    total_in_custom = result.get('total_emails_in_custom_folders', 0)
    drafts = result.get('drafts', [])
    sent = result.get('sent', [])
    all_outgoing = drafts + sent

    # OUTPUT-EXISTENCE GATE: if no work was done at all, score=0
    has_custom_folders = custom_folder_count > 0
    has_outgoing = len(all_outgoing) > 0
    if not has_custom_folders and not has_outgoing:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No work done: no folders created and no emails drafted or sent"
        }

    # ================================================================
    # CRITERION 1: At least 2 custom IMAP folders created (25 pts)
    # ================================================================
    try:
        if custom_folder_count >= min_folders:
            score += 25
            subscores['folders_created'] = True
            feedback_parts.append(f"Folders created: {custom_folder_count} ({list(custom_folders.keys())[:5]})")
        elif custom_folder_count == 1:
            score += 10
            subscores['folders_created'] = False
            feedback_parts.append(f"Only 1 folder created (need {min_folders}+)")
        else:
            subscores['folders_created'] = False
            feedback_parts.append(f"No custom folders created")
    except Exception as e:
        feedback_parts.append(f"Folder check error: {e}")

    # ================================================================
    # CRITERION 2: Inbox substantially reduced (25 pts)
    # ================================================================
    try:
        emails_moved = initial_inbox - inbox_count
        if inbox_count < (initial_inbox - min_moved):
            score += 25
            subscores['inbox_reduced'] = True
            feedback_parts.append(f"Inbox reduced: {inbox_count} remaining ({emails_moved} moved)")
        elif emails_moved >= 5:
            score += 10
            subscores['inbox_reduced'] = False
            feedback_parts.append(f"Inbox partially reduced: {inbox_count} remaining ({emails_moved} moved, need {min_moved}+)")
        else:
            subscores['inbox_reduced'] = False
            feedback_parts.append(f"Inbox barely changed: {inbox_count} remaining")
    except Exception as e:
        feedback_parts.append(f"Inbox count check error: {e}")

    # ================================================================
    # CRITERION 3: Custom folders collectively have 15+ emails (15 pts)
    # ================================================================
    try:
        if total_in_custom >= 15:
            score += 15
            subscores['folders_populated'] = True
            feedback_parts.append(f"Folders populated: {total_in_custom} emails across {custom_folder_count} folders")
        elif total_in_custom >= 5:
            score += 7
            subscores['folders_populated'] = False
            feedback_parts.append(f"Folders partially populated: {total_in_custom} emails (need 15+)")
        else:
            subscores['folders_populated'] = False
            feedback_parts.append(f"Folders mostly empty: {total_in_custom} emails")
    except Exception as e:
        feedback_parts.append(f"Folder population check error: {e}")

    # ================================================================
    # CRITERION 4: Summary email to devops-team@techcorp.org (25 pts)
    # ================================================================
    try:
        summary_found = False
        for email in all_outgoing:
            to_addr = email.get('to', '').lower()
            if summary_recipient in to_addr:
                summary_found = True
                break
        if summary_found:
            score += 25
            subscores['summary_sent'] = True
            feedback_parts.append(f"Summary email to {summary_recipient} found")
        else:
            subscores['summary_sent'] = False
            feedback_parts.append(f"No email to {summary_recipient} found")
    except Exception as e:
        feedback_parts.append(f"Summary email check error: {e}")

    # ================================================================
    # CRITERION 5: Summary email subject is relevant (10 pts)
    # ================================================================
    try:
        subject_ok = False
        relevant_terms = ['triage', 'inbox', 'mailing', 'organize', 'list', 'sorted', 'complete']
        for email in all_outgoing:
            to_addr = email.get('to', '').lower()
            subject = email.get('subject', '').lower()
            if summary_recipient in to_addr:
                if any(t in subject for t in relevant_terms):
                    subject_ok = True
                    break
        if subject_ok:
            score += 10
            subscores['subject_relevant'] = True
            feedback_parts.append("Summary email subject is relevant")
        else:
            subscores['subject_relevant'] = False
            feedback_parts.append("Summary email subject not relevant or missing")
    except Exception as e:
        feedback_parts.append(f"Subject check error: {e}")

    # VLM bonus check (up to 5 extra points for visual confirmation, capped at 100)
    try:
        query_vlm = env_info.get('query_vlm')
        get_final_screenshot = env_info.get('get_final_screenshot')
        if query_vlm and traj and get_final_screenshot:
            final_screenshot = get_final_screenshot(traj)
            if final_screenshot:
                vlm_result = query_vlm(
                    image=final_screenshot,
                    prompt="""Analyze this BlueMail screenshot. In JSON format:
{"folders_visible_in_sidebar": true/false, "inbox_organized": true/false, "explanation": "brief"}
Are multiple folders visible in the sidebar? Does the inbox appear organized?"""
                )
                vlm_text = str(vlm_result).lower() if vlm_result else ''
                if 'folders_visible_in_sidebar": true' in vlm_text or ('folder' in vlm_text and 'sidebar' in vlm_text):
                    bonus = min(5, 100 - score)
                    score += bonus
                    feedback_parts.append("VLM: Folders visible in sidebar")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")

    passed = score >= 70

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "inbox_count": inbox_count,
            "custom_folder_count": custom_folder_count,
            "custom_folders": custom_folders,
            "total_in_custom": total_in_custom,
            "draft_count": result.get('draft_count', 0)
        }
    }
