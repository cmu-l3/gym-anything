#!/usr/bin/env python3
"""
Verifier for proposal_asset_compilation task.

SCORING CRITERIA:
1. Folder 'Falcon_Assets' created in Documents (10 pts)
2. 'specs.txt' saved with correct content (20 pts)
3. 'budget.csv' saved with correct content (20 pts)
4. 'nda.pdf' saved with correct content (20 pts)
5. Confirmation email sent to 'manager@internal.corp' (20 pts)
6. Confirmation email subject contains 'Falcon' and 'Assets' (10 pts)

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_proposal_asset_compilation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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
    
    # ----------------------------------------------------------------
    # 1. Folder Verification (10 pts)
    # ----------------------------------------------------------------
    if result.get('folder_exists', False):
        score += 10
        feedback_parts.append("Folder 'Falcon_Assets' created")
    else:
        feedback_parts.append("Folder 'Falcon_Assets' NOT found")

    # ----------------------------------------------------------------
    # 2-4. File Content Verification (60 pts total)
    # ----------------------------------------------------------------
    found_files = result.get('found_files', {})
    expected_hashes = result.get('expected_hashes', {})
    task_start = result.get('task_start', 0)

    # Required files
    files_to_check = ["specs.txt", "budget.csv", "nda.pdf"]
    
    for fname in files_to_check:
        if fname in found_files:
            file_info = found_files[fname]
            
            # Check content hash
            if file_info.get('md5') == expected_hashes.get(fname):
                # Check timestamp (anti-gaming: must be created/modified during task)
                if file_info.get('mtime', 0) > task_start:
                    score += 20
                    feedback_parts.append(f"{fname} saved correctly")
                else:
                    # Content correct but stale timestamp? (Unlikely in this setup, but good check)
                    score += 10
                    feedback_parts.append(f"{fname} content correct but timestamp old")
            else:
                feedback_parts.append(f"{fname} content mismatch (wrong file?)")
        else:
            feedback_parts.append(f"{fname} missing")

    # ----------------------------------------------------------------
    # 5-6. Email Confirmation Verification (30 pts total)
    # ----------------------------------------------------------------
    sent_emails = result.get('sent_emails', [])
    email_sent = False
    subject_correct = False
    
    target_recipient = "manager@internal.corp"
    
    for email_data in sent_emails:
        to_field = str(email_data.get('to', '')).lower()
        subject = str(email_data.get('subject', '')).lower()
        
        if target_recipient in to_field:
            email_sent = True
            if "falcon" in subject and "assets" in subject:
                subject_correct = True
            break
    
    if email_sent:
        score += 20
        feedback_parts.append("Confirmation email sent")
        if subject_correct:
            score += 10
            feedback_parts.append("Subject line correct")
        else:
            feedback_parts.append("Subject line missing keywords")
    else:
        feedback_parts.append("No confirmation email found to manager@internal.corp")

    # ----------------------------------------------------------------
    # Final Result
    # ----------------------------------------------------------------
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }