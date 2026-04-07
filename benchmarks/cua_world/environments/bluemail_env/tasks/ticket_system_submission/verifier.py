#!/usr/bin/env python3
"""
Verifier for ticket_system_submission task.

SCORING CRITERIA:
1. Email forwarded to tickets@localhost (10 pts)
2. Subject starts with "[TICKET]" (20 pts)
3. Body contains "Priority: Normal" (10 pts)
4. Body contains "Tags: triage, bug" (10 pts)
5. Folder "Processed-Tickets" created (15 pts)
6. Original email moved to folder (20 pts)
7. Content check: archived email is relevant (contains bug/error keywords) (15 pts)

Total: 100
Pass Threshold: 70
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ticket_system_submission(traj, env_info, task_info):
    """Verify ticket submission workflow."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_keywords = metadata.get('target_keywords', ['error', 'bug', 'fail', 'problem'])

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Check Sent Email
    sent_data = result.get("sent_email_data")
    if result.get("sent_email_found") and sent_data:
        score += 10
        feedback.append("Email forwarded to tickets@localhost")
        
        # Check Subject
        subject = sent_data.get("subject", "")
        if subject.strip().startswith("[TICKET]"):
            score += 20
            feedback.append("Subject prefix correct")
        else:
            feedback.append(f"Subject format incorrect: '{subject}'")

        # Check Body Metadata
        body = sent_data.get("body_start", "")
        if "Priority: Normal" in body:
            score += 10
            feedback.append("Priority tag found")
        else:
            feedback.append("Missing 'Priority: Normal'")
            
        if "Tags: triage, bug" in body:
            score += 10
            feedback.append("Tags found")
        else:
            feedback.append("Missing 'Tags: triage, bug'")
    else:
        feedback.append("No email found sent to tickets@localhost")

    # 2. Check Archive Folder
    if result.get("archive_folder_exists"):
        score += 15
        feedback.append("Processed-Tickets folder created")
        
        count = result.get("archived_email_count", 0)
        if count >= 1:
            score += 20
            feedback.append(f"Original email archived ({count} found)")
            
            # 3. Content Relevance Check
            subjects = result.get("archived_email_subjects", [])
            relevant = False
            for subj in subjects:
                if any(k in subj.lower() for k in target_keywords):
                    relevant = True
                    break
            
            if relevant:
                score += 15
                feedback.append("Archived email appears relevant (technical keywords found)")
            else:
                feedback.append("Archived email may not be technical (keywords not found in subject)")
        else:
            feedback.append("Processed-Tickets folder is empty")
    else:
        feedback.append("Processed-Tickets folder NOT created")

    # VLM Trajectory Check (Bonus/Confirmation)
    # If score is borderline, we could check frames, but file verification is robust here.
    # We'll just append a note if no sent email was found programmatically but VLM sees it.
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }