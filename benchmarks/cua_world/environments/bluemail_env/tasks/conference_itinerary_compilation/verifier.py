#!/usr/bin/env python3
"""
Verifier for conference_itinerary_compilation task.

SCORING CRITERIA:
1. Folder 'Dublin-Events' created (20 pts)
2. Folder contains 3+ emails (20 pts)
3. Moved emails contain social keywords (relevance check) (20 pts)
4. Summary email sent to 'team@devrel.com' (20 pts)
5. Summary email content mentions the subjects of the moved emails (20 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_conference_itinerary(traj, env_info, task_info):
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

    maildir = result.get('maildir_analysis', {})
    
    score = 0
    feedback = []

    # 1. Check Folder Creation (20 pts)
    if maildir.get('folder_created'):
        score += 20
        feedback.append("Folder 'Dublin-Events' created.")
    else:
        feedback.append("Folder 'Dublin-Events' NOT found.")

    # 2. Check Emails Moved (20 pts)
    emails_in_folder = maildir.get('emails_in_folder', [])
    count = len(emails_in_folder)
    
    if count >= 3:
        score += 20
        feedback.append(f"Folder populated with {count} emails (Target: 3+).")
    elif count > 0:
        score += 10
        feedback.append(f"Folder partially populated with {count} emails (Target: 3+).")
    else:
        feedback.append("Folder is empty.")

    # 3. Check Relevance (Keywords) (20 pts)
    # The export script pre-calculates 'has_keyword'
    relevant_count = sum(1 for e in emails_in_folder if e.get('has_keyword'))
    if count > 0:
        if relevant_count >= 2: # Allow some noise
            score += 20
            feedback.append(f"{relevant_count} emails contain event keywords.")
        elif relevant_count == 1:
            score += 10
            feedback.append("Only 1 email contains event keywords.")
        else:
            feedback.append("Moved emails do not seem related to social events.")
    else:
        feedback.append("No emails to check for relevance.")

    # 4. Check Sent Email Recipient (20 pts)
    sent_emails = maildir.get('sent_emails', [])
    target_recipient = "team@devrel.com"
    
    found_summary = None
    for email in sent_emails:
        if target_recipient in email.get('to', '').lower():
            found_summary = email
            break
            
    if found_summary:
        score += 20
        feedback.append(f"Summary email sent to {target_recipient}.")
    else:
        feedback.append(f"No email sent to {target_recipient}.")

    # 5. Check Summary Content (20 pts)
    # Does the summary body/subject contain the subjects of the moved emails?
    if found_summary and count > 0:
        summary_text = (found_summary.get('subject', '') + " " + found_summary.get('body', '')).lower()
        
        matches = 0
        moved_subjects = [e.get('subject', '').lower() for e in emails_in_folder if e.get('subject')]
        
        # We check if significant parts of the moved email subjects appear in the summary
        # Simple heuristic: check if at least one unique word (len > 4) from the subject exists in summary
        # Or exact substring match for shorter subjects
        
        for subj in moved_subjects:
            # Clean subject (remove Re:, Fwd:, etc)
            clean_subj = subj.replace("re:", "").replace("fwd:", "").strip()
            if clean_subj in summary_text:
                matches += 1
            else:
                # Fallback: check intersection of significant words
                subj_words = set(w for w in clean_subj.split() if len(w) > 4)
                if subj_words and any(w in summary_text for w in subj_words):
                    matches += 1

        if matches >= 2:
            score += 20
            feedback.append(f"Summary correctly references {matches} event emails.")
        elif matches == 1:
            score += 10
            feedback.append("Summary references only 1 event email.")
        else:
            feedback.append("Summary does not seem to reference the moved emails.")
    elif found_summary:
        feedback.append("Summary sent, but no events were organized to cross-reference.")

    # VLM Trajectory Check (Bonus / Anti-Gaming) - Optional in this specific logic but good to mention
    # We rely primarily on file state here as it's robust for this specific task type.

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }