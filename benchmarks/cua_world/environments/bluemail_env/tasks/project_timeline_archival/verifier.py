#!/usr/bin/env python3
"""
Verifier for project_timeline_archival task.

Logic:
1. Verify 'Project-Exmh' folder exists and has emails.
2. Sort the emails actually IN that folder by timestamp to find Oldest and Newest.
   (This is robust: if agent missed some emails, we only grade based on what they successfully moved).
3. Check Sent items for:
   - Reply to Oldest (matching In-Reply-To or Subject pattern)
   - Forward of Newest (matching Subject pattern and To address)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_project_timeline_archival(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment error: copy unavailable"}

    metadata = task_info.get('metadata', {})
    expected_recipient = metadata.get('archive_recipient', 'archive@internal.org').lower()

    # Load result
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
    feedback = []

    # 2. Verify Folder Creation & Population (30 pts)
    folder_exists = result.get("folder_exists", False)
    project_emails = result.get("project_emails", [])
    email_count = len(project_emails)

    if folder_exists:
        score += 10
        feedback.append("Folder 'Project-Exmh' created.")
    else:
        feedback.append("Folder 'Project-Exmh' NOT found.")

    if email_count >= 5:
        score += 20
        feedback.append(f"Folder populated with {email_count} emails.")
    elif email_count > 0:
        score += 10
        feedback.append(f"Folder populated but count low ({email_count} < 5).")
    else:
        feedback.append("Folder is empty.")

    # 3. Verify Inbox Cleanup (10 pts)
    # Baseline is ~50. If they moved ~5-10 exmh emails, inbox should be <= 45.
    inbox_count = result.get("inbox_count", 50)
    if inbox_count <= 45:
        score += 10
        feedback.append("Inbox cleanup verified.")
    else:
        feedback.append(f"Inbox count ({inbox_count}) suggests cleanup incomplete.")

    # 4. Timeline Analysis (Ground Truth Calculation)
    if email_count > 0:
        # Sort by timestamp
        sorted_emails = sorted(project_emails, key=lambda x: x.get('timestamp', 0))
        
        oldest_email = sorted_emails[0]
        newest_email = sorted_emails[-1]
        
        oldest_id = oldest_email.get('message_id', '')
        oldest_subj = oldest_email.get('subject', '').lower()
        
        newest_subj = newest_email.get('subject', '') # Keep case for forwarding check might be safer, but usually we normalize
        
        sent_emails = result.get("sent_emails", [])
        
        # 5. Verify Reply to Oldest (30 pts)
        reply_found = False
        for sent in sent_emails:
            # Criteria A: In-Reply-To matches
            if oldest_id and sent.get('in_reply_to') == oldest_id:
                reply_found = True
                break
            
            # Criteria B: Subject matches Re: [Oldest Subject]
            # Heuristic: sent subject contains oldest subject
            sent_subj = sent.get('subject', '').lower()
            if "re:" in sent_subj and (oldest_subj.replace("re:", "").strip() in sent_subj):
                reply_found = True
                break
                
        if reply_found:
            score += 30
            feedback.append("Correctly replied to the oldest email.")
        else:
            feedback.append(f"Failed to reply to oldest email (Subject: {oldest_email.get('subject')}).")

        # 6. Verify Forward of Newest (30 pts)
        forward_found = False
        for sent in sent_emails:
            sent_to = sent.get('to', '').lower()
            sent_subj = sent.get('subject', '')
            
            # Criteria A: Recipient matches
            if expected_recipient in sent_to:
                # Criteria B: Subject indicates forward of newest
                # Look for "Project Closeout" AND key parts of original subject
                if "Project Closeout" in sent_subj:
                    # Check if original subject content is present
                    # Normalize simple strings
                    clean_newest = newest_subj.replace("Re:", "").replace("Fwd:", "").strip()
                    if clean_newest in sent_subj or clean_newest[:20] in sent_subj:
                        forward_found = True
                        break
        
        if forward_found:
            score += 30
            feedback.append("Correctly forwarded the newest email with proper subject.")
        else:
            feedback.append(f"Failed to forward newest email (Subject: {newest_subj}) to archive.")

    else:
        feedback.append("Cannot verify timeline actions because project folder is empty.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }