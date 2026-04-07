#!/usr/bin/env python3
"""
Verifier for mailbox_storage_quota_cleanup task.

Criteria:
1. Storage Reclaimed (40 pts): Total Maildir size < 5MB (implies large files deleted and trash emptied).
2. Large Files Removed (20 pts): Specific large emails are not in Inbox or Trash.
3. Trash Emptied (10 pts): Trash folder has 0 items.
4. Content Preserved (30 pts): >40 normal emails remain in Inbox.

Total: 100
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mailbox_storage_quota_cleanup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata
    metadata = task_info.get('metadata', {})
    target_max_size = metadata.get('target_max_size_bytes', 5242880) # 5MB
    min_preserved = metadata.get('min_preserved_emails', 40)
    
    # Load Result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    final_size = result.get('final_maildir_size_bytes', 999999999)
    inbox_count = result.get('inbox_email_count', 0)
    trash_count = result.get('trash_item_count', 0)
    remaining_inbox = result.get('remaining_large_in_inbox', [])
    remaining_trash = result.get('remaining_large_in_trash', [])
    
    # 1. Storage Reclaimed (40 pts)
    # The maildir started at ~25MB+ (5x5MB files + normal emails).
    # Normal emails take up very little space.
    if final_size < target_max_size:
        score += 40
        feedback_parts.append(f"Storage quota reclaimed (Size: {final_size/1024/1024:.2f}MB)")
    else:
        feedback_parts.append(f"Storage still high: {final_size/1024/1024:.2f}MB (Target < 5MB)")

    # 2. Large Files Removed specifically (20 pts)
    # Checks if specific subjects are gone from everywhere
    if len(remaining_inbox) == 0 and len(remaining_trash) == 0:
        score += 20
        feedback_parts.append("All large asset emails removed")
    else:
        if len(remaining_inbox) > 0:
            feedback_parts.append(f"{len(remaining_inbox)} large emails left in Inbox")
        if len(remaining_trash) > 0:
            feedback_parts.append(f"{len(remaining_trash)} large emails left in Trash")

    # 3. Trash Emptied (10 pts)
    # Even if size is low, explicitly check item count for completeness
    if trash_count == 0:
        score += 10
        feedback_parts.append("Trash is empty")
    else:
        feedback_parts.append(f"Trash not empty ({trash_count} items remaining)")

    # 4. Content Preserved (30 pts)
    # We started with 45 normal emails + 5 large ones = 50 total.
    # We expect 5 large ones gone, so ~45 remaining.
    # Allowing for accidental deletion of a few, threshold is 40.
    # Note: large files count towards inbox_count if not deleted, so we subtract them from the count logic 
    # (though verifier logic 'inbox_count' typically includes everything in folder).
    # To be precise: The result.json 'inbox_email_count' counts ALL files in inbox.
    # If large files are present, they are counted.
    # However, if large files are present, criteria 2 fails.
    # Here we want to ensure *normal* emails are preserved.
    # Approximate: normal_remaining = inbox_count - len(remaining_inbox)
    
    normal_estimated = inbox_count - len(remaining_inbox)
    
    if normal_estimated >= min_preserved:
        score += 30
        feedback_parts.append(f"Normal correspondence preserved ({normal_estimated} emails)")
    elif normal_estimated >= 20:
        score += 15
        feedback_parts.append(f"Some normal emails lost ({normal_estimated} remaining)")
    else:
        feedback_parts.append(f"Too many normal emails deleted ({normal_estimated} remaining)")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }