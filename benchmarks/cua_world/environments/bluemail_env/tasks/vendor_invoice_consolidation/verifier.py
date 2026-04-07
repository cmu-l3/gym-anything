#!/usr/bin/env python3
"""
Verifier for vendor_invoice_consolidation task.

Scoring Criteria:
1. Local folder 'Invoices' created (10 pts)
2. Files downloaded correctly (30 pts - 10 per file)
   - Must match expected filenames
   - Must be created *during* the task (anti-gaming)
3. Email composed to correct recipient (10 pts)
4. Email subject contains 'Invoice' (5 pts)
5. Attachments attached to email (45 pts - 15 per file)

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_vendor_invoice_consolidation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from VM
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
    
    # 1. Check Local Folder (10 pts)
    if result.get('target_dir_exists', False):
        score += 10
        feedback_parts.append("Invoices folder created")
    else:
        feedback_parts.append("Invoices folder NOT found")

    # 2. Check Downloaded Files (30 pts)
    files = result.get('downloaded_files', [])
    download_score = 0
    downloaded_names = []
    
    for f in files:
        if f.get('exists') and f.get('created_during_task'):
            download_score += 10
            downloaded_names.append(f['name'])
    
    score += download_score
    if download_score > 0:
        feedback_parts.append(f"Downloaded {len(downloaded_names)}/3 files")
    else:
        feedback_parts.append("No files downloaded")

    # 3. Check Sent Email
    email_data = result.get('sent_email', {})
    
    if email_data.get('found'):
        # Recipient (10 pts)
        if "accounting@company.com" in email_data.get('recipient', ''):
            score += 10
            feedback_parts.append("Recipient correct")
        else:
            feedback_parts.append("Wrong recipient")

        # Subject (5 pts)
        subject = email_data.get('subject', '')
        if "Invoice" in subject or "invoice" in subject:
            score += 5
            feedback_parts.append("Subject correct")
        else:
            feedback_parts.append("Subject missing keyword 'Invoice'")

        # Attachments (45 pts)
        # We expect 3 attachments. 15 pts each.
        att_count = email_data.get('attachment_count', 0)
        att_names = email_data.get('attachment_names', [])
        
        # Verify relevant attachments are present (checking substrings)
        valid_atts = 0
        expected_substrings = ["acme", "beta", "gamma"]
        
        for substring in expected_substrings:
            if any(substring in name.lower() for name in att_names):
                valid_atts += 1
        
        att_score = valid_atts * 15
        score += att_score
        feedback_parts.append(f"Attachments: {valid_atts}/3 attached correctly")
        
    else:
        feedback_parts.append("No consolidated email found in Sent or Drafts")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }