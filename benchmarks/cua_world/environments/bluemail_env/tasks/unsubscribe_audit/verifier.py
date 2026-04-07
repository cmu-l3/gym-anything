#!/usr/bin/env python3
"""
Verifier for unsubscribe_audit task.

Scoring Criteria:
1. Unsubscribe folder created (15 pts)
2. 8+ emails moved to that folder (20 pts)
3. Moved emails come from at least 2 distinct mailing lists (10 pts)
4. 2+ Unsubscribe request drafts created (addressed to list admins) (25 pts)
5. Admin notification draft created (to it-admin@techcorp.org) (20 pts)
6. Admin notification content quality (mentions lists) (10 pts)

Pass Threshold: 60/100
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_unsubscribe_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    score = 0
    feedback_parts = []
    
    # Data extraction
    unsub_folders = result.get("unsubscribe_folders", [])
    drafts = result.get("drafts", [])
    sent = result.get("sent", [])
    all_outgoing = drafts + sent
    
    # --- Criterion 1: Folder Creation (15 pts) ---
    target_folder = None
    if unsub_folders:
        score += 15
        target_folder = unsub_folders[0] # Take the first matching one
        feedback_parts.append(f"Folder '{target_folder['name']}' created")
    else:
        feedback_parts.append("No 'Unsubscribe' folder found")
        # Critical failure path check? No, continue to check drafts.

    # --- Criterion 2: Emails Moved (20 pts) ---
    moved_count = target_folder["email_count"] if target_folder else 0
    if moved_count >= 8:
        score += 20
        feedback_parts.append(f"Moved {moved_count} emails (>=8)")
    elif moved_count >= 3:
        score += 10
        feedback_parts.append(f"Moved {moved_count} emails (partial credit)")
    else:
        feedback_parts.append(f"Moved {moved_count} emails (insufficient)")

    # --- Criterion 3: List Diversity (10 pts) ---
    lists_detected = target_folder.get("distinct_lists_detected", []) if target_folder else []
    if len(lists_detected) >= 2:
        score += 10
        feedback_parts.append(f"Emails from {len(lists_detected)} lists identified: {', '.join(lists_detected)}")
    elif len(lists_detected) == 1:
        score += 5
        feedback_parts.append("Emails from only 1 list found")
    else:
        feedback_parts.append("No distinct mailing lists identified in folder")

    # --- Criterion 4: Unsubscribe Drafts (25 pts) ---
    # Look for emails to admin/request addresses or with "unsubscribe" in body
    unsub_draft_count = 0
    
    # Common list admin patterns or keywords
    list_keywords = ['request', 'admin', 'owner', 'unsubscribe', 'leave', 'majordomo', 'listserv']
    
    for email_obj in all_outgoing:
        to_addr = email_obj.get("to", "").lower()
        subject = email_obj.get("subject", "").lower()
        body = email_obj.get("body", "").lower()
        
        # Don't count the admin notification here
        if "it-admin@techcorp.org" in to_addr:
            continue
            
        # Check if it looks like an unsubscribe email
        is_list_addr = any(k in to_addr for k in list_keywords)
        has_unsub_keyword = "unsubscribe" in body or "remove" in body or "leave" in body or "unsubscribe" in subject
        
        if is_list_addr and has_unsub_keyword:
            unsub_draft_count += 1
            
    if unsub_draft_count >= 2:
        score += 25
        feedback_parts.append(f"Created {unsub_draft_count} unsubscribe requests")
    elif unsub_draft_count == 1:
        score += 15
        feedback_parts.append("Created 1 unsubscribe request")
    else:
        feedback_parts.append("No valid unsubscribe requests found")

    # --- Criterion 5: Admin Notification (20 pts) ---
    admin_notif = None
    for email_obj in all_outgoing:
        if "it-admin@techcorp.org" in email_obj.get("to", "").lower():
            admin_notif = email_obj
            break
            
    if admin_notif:
        score += 20
        feedback_parts.append("Admin notification drafted")
    else:
        feedback_parts.append("No email to it-admin@techcorp.org found")

    # --- Criterion 6: Notification Quality (10 pts) ---
    if admin_notif:
        body = admin_notif.get("body", "").lower()
        subject = admin_notif.get("subject", "").lower()
        
        # Check for list names from the corpus
        corpus_lists = ['spamassassin', 'sadev', 'satalk', 'ilug', 'zzzzteana', 'exmh', 'irr']
        mentioned_lists = sum(1 for lst in corpus_lists if lst in body or lst in subject)
        
        if mentioned_lists >= 2:
            score += 10
            feedback_parts.append(f"Notification mentions {mentioned_lists} lists")
        elif mentioned_lists == 1:
            score += 5
            feedback_parts.append("Notification mentions 1 list")
        else:
            feedback_parts.append("Notification is vague (no specific lists mentioned)")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }