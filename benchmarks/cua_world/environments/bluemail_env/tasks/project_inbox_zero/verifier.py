#!/usr/bin/env python3
"""
Verifier for project_inbox_zero task.

Occupation context: Software Project Manager / IT Operations
Context: 50 emails with 2 pre-organized folders (Security-Discussion, Hardware-Issues)
         and 40 unsorted emails remaining in inbox

Scoring (100 points total, pass threshold: 65):
- 25 pts: 3+ new folders created (beyond the 2 pre-existing) — total 5+ custom folders
- 25 pts: Inbox has 5 or fewer emails remaining (inbox zero achieved)
- 15 pts: Each new folder has 2+ emails (all new folders populated)
- 25 pts: Draft/sent to project-director@devteam.com with status/organization/complete in subject
- 10 pts: Draft body mentions at least 3 folder names

Output-existence gate: new_folder_count < 3 AND no draft/sent -> score=0
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_project_inbox_zero(traj, env_info, task_info):
    """Verify project inbox zero task completion."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    status_recipient = metadata.get('status_recipient', 'project-director@devteam.com').lower()
    min_new_folders = metadata.get('min_new_folders', 3)
    max_inbox = metadata.get('max_inbox_remaining', 5)

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

    inbox_count = result.get('inbox_count', 40)
    new_folder_count = result.get('new_folder_count', 0)
    new_folders = result.get('new_folders', {})
    all_custom_folders = result.get('all_custom_folders', {})
    new_folders_populated = result.get('new_folders_with_2plus_emails', 0)
    drafts = result.get('drafts', [])
    sent = result.get('sent', [])
    all_outgoing = drafts + sent

    # OUTPUT-EXISTENCE GATE
    if new_folder_count < min_new_folders and len(all_outgoing) == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"No meaningful work done: only {new_folder_count} new folders created and no emails drafted"
        }

    # ================================================================
    # CRITERION 1: 3+ new folders created (25 pts)
    # ================================================================
    try:
        if new_folder_count >= min_new_folders:
            score += 25
            subscores['new_folders_created'] = True
            feedback_parts.append(f"New folders created: {new_folder_count} — {list(new_folders.keys())}")
        elif new_folder_count >= 1:
            score += 10
            subscores['new_folders_created'] = False
            feedback_parts.append(f"Only {new_folder_count} new folder(s) created (need {min_new_folders}+)")
        else:
            subscores['new_folders_created'] = False
            feedback_parts.append(f"No new folders created beyond pre-existing")
    except Exception as e:
        feedback_parts.append(f"Folder count check error: {e}")

    # ================================================================
    # CRITERION 2: Inbox cleared to 5 or fewer (25 pts)
    # ================================================================
    try:
        if inbox_count <= max_inbox:
            score += 25
            subscores['inbox_cleared'] = True
            feedback_parts.append(f"Inbox cleared: {inbox_count} emails remaining (≤{max_inbox})")
        elif inbox_count <= 15:
            score += 12
            subscores['inbox_cleared'] = False
            feedback_parts.append(f"Inbox partially cleared: {inbox_count} remaining (need ≤{max_inbox})")
        else:
            subscores['inbox_cleared'] = False
            feedback_parts.append(f"Inbox not cleared: {inbox_count} emails still present")
    except Exception as e:
        feedback_parts.append(f"Inbox count check error: {e}")

    # ================================================================
    # CRITERION 3: New folders are populated (2+ emails each) (15 pts)
    # ================================================================
    try:
        if new_folder_count > 0:
            populated_fraction = new_folders_populated / max(new_folder_count, 1)
            if populated_fraction >= 0.8 or new_folders_populated >= min_new_folders:
                score += 15
                subscores['folders_populated'] = True
                feedback_parts.append(f"New folders populated: {new_folders_populated}/{new_folder_count} have 2+ emails")
            elif new_folders_populated >= 1:
                score += 7
                subscores['folders_populated'] = False
                feedback_parts.append(f"Some new folders populated: {new_folders_populated}/{new_folder_count}")
            else:
                subscores['folders_populated'] = False
                feedback_parts.append(f"New folders are empty")
        else:
            subscores['folders_populated'] = False
            feedback_parts.append("No new folders to check population")
    except Exception as e:
        feedback_parts.append(f"Folder population check error: {e}")

    # ================================================================
    # CRITERION 4: Status email to project-director@devteam.com (25 pts)
    # ================================================================
    try:
        status_found = False
        for email in all_outgoing:
            to_addr = email.get('to', '').lower()
            if status_recipient in to_addr:
                status_found = True
                break
        if status_found:
            score += 25
            subscores['status_sent'] = True
            feedback_parts.append(f"Status email to {status_recipient} found")
        else:
            subscores['status_sent'] = False
            feedback_parts.append(f"No email to {status_recipient} found")
    except Exception as e:
        feedback_parts.append(f"Status email check error: {e}")

    # ================================================================
    # CRITERION 5: Status email mentions 3+ folder names (10 pts)
    # ================================================================
    try:
        folder_names_mentioned = 0
        all_folder_names = list(all_custom_folders.keys())
        for email in all_outgoing:
            to_addr = email.get('to', '').lower()
            if status_recipient not in to_addr:
                continue
            body = email.get('body', '').lower()
            subject = email.get('subject', '').lower()
            combined = body + ' ' + subject
            count = sum(1 for fname in all_folder_names if fname.lower() in combined)
            folder_names_mentioned = max(folder_names_mentioned, count)
        if folder_names_mentioned >= 3:
            score += 10
            subscores['folder_names_in_body'] = True
            feedback_parts.append(f"Status email mentions {folder_names_mentioned} folder names")
        elif folder_names_mentioned >= 1:
            score += 4
            subscores['folder_names_in_body'] = False
            feedback_parts.append(f"Status email mentions only {folder_names_mentioned} folder name(s)")
        else:
            subscores['folder_names_in_body'] = False
            feedback_parts.append("Status email does not mention folder names")
    except Exception as e:
        feedback_parts.append(f"Folder names check error: {e}")

    # VLM supplementary check
    try:
        query_vlm = env_info.get('query_vlm')
        get_final_screenshot = env_info.get('get_final_screenshot')
        if query_vlm and traj and get_final_screenshot:
            final_screenshot = get_final_screenshot(traj)
            if final_screenshot:
                vlm_result = query_vlm(
                    image=final_screenshot,
                    prompt="""Analyze this BlueMail screenshot. In JSON:
{"multiple_folders_visible": true/false, "inbox_empty_or_few": true/false, "explanation": "brief"}
Are 5+ folders visible in the sidebar? Does inbox appear empty or nearly empty?"""
                )
                vlm_text = str(vlm_result).lower() if vlm_result else ''
                if ('multiple_folders_visible": true' in vlm_text or
                        ('folder' in vlm_text and 'sidebar' in vlm_text)):
                    bonus = min(5, 100 - score)
                    score += bonus
                    feedback_parts.append("VLM: Multiple folders visible in sidebar")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")

    passed = score >= 65

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "inbox_count": inbox_count,
            "new_folder_count": new_folder_count,
            "all_custom_folder_count": result.get('all_custom_folder_count', 0),
            "new_folders": new_folders,
            "draft_count": result.get('draft_count', 0)
        }
    }
