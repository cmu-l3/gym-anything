#!/usr/bin/env python3
"""
Verifier for community_question_triage task.

Scoring Breakdown (100 pts total):
1. Folder Creation (10 pts): Both folders exist.
2. Inbox Cleared (10 pts): Inbox has < 5 emails.
3. Sorting Accuracy (30 pts):
   - Correctly moving 'Re:' emails to Community-Replies.
   - Correctly moving non-'Re:' emails to New-Topics.
4. Flagging Accuracy (40 pts):
   - Precision/Recall for flagging emails with '?' in New-Topics.
5. Reporting (10 pts): Status email sent.
"""

import json
import os
import sys
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_community_question_triage(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env missing"}

    # Load result
    import tempfile
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

    # 1. Folder Creation (10 pts)
    folders = result.get('folders_created', {})
    if folders.get('Community-Replies') and folders.get('New-Topics'):
        score += 10
        feedback.append("Folders created correctly.")
    elif folders.get('Community-Replies') or folders.get('New-Topics'):
        score += 5
        feedback.append("Only one folder created.")
    else:
        feedback.append("No required folders created.")

    # 2. Inbox Cleared (10 pts)
    inbox_count = result.get('inbox_count', 999)
    if inbox_count < 5:
        score += 10
        feedback.append("Inbox cleared.")
    else:
        feedback.append(f"Inbox not cleared ({inbox_count} remain).")

    # 3. Sorting Accuracy (30 pts)
    # Logic: Check contents of destination folders
    replies_emails = result.get('community_replies_emails', [])
    topics_emails = result.get('new_topics_emails', [])
    
    total_sorted = len(replies_emails) + len(topics_emails)
    if total_sorted == 0:
        feedback.append("No emails moved to custom folders.")
    else:
        # Check Replies Folder
        replies_correct = 0
        replies_wrong = 0
        for em in replies_emails:
            subj = em.get('subject', '').strip().lower()
            if subj.startswith('re:') or subj.startswith('re '): # loose check for re
                replies_correct += 1
            else:
                replies_wrong += 1
        
        # Check Topics Folder
        topics_correct = 0
        topics_wrong = 0
        for em in topics_emails:
            subj = em.get('subject', '').strip().lower()
            if subj.startswith('re:') or subj.startswith('re '):
                topics_wrong += 1
            else:
                topics_correct += 1

        # Calculate score
        # We penalize wrong moves more than missing moves to prevent random dumping
        total_errors = replies_wrong + topics_wrong
        total_correct = replies_correct + topics_correct
        
        # Avoid div/0
        accuracy = total_correct / (total_sorted if total_sorted > 0 else 1)
        
        # Scale score: If accuracy > 90%, full points. 
        if total_sorted > 10: # Minimum effort threshold
            if accuracy > 0.9:
                score += 30
                feedback.append("Sorting accuracy excellent.")
            elif accuracy > 0.7:
                score += 20
                feedback.append("Sorting accuracy good.")
            elif accuracy > 0.5:
                score += 10
                feedback.append("Sorting accuracy fair.")
            else:
                feedback.append(f"Sorting accuracy poor ({int(accuracy*100)}%).")
        else:
            feedback.append("Too few emails sorted to judge accuracy.")

    # 4. Flagging Accuracy (40 pts)
    # Only checks the 'New-Topics' folder as per instructions
    topics_emails = result.get('new_topics_emails', [])
    
    tp = 0 # True Positive (Is Question AND Flagged)
    fp = 0 # False Positive (Not Question AND Flagged)
    fn = 0 # False Negative (Is Question AND Not Flagged)
    tn = 0 # True Negative (Not Question AND Not Flagged)
    
    question_count = 0
    
    for em in topics_emails:
        subj = em.get('subject', '')
        is_question = '?' in subj
        is_flagged = em.get('is_flagged', False)
        
        if is_question:
            question_count += 1
            if is_flagged:
                tp += 1
            else:
                fn += 1
        else:
            if is_flagged:
                fp += 1
            else:
                tn += 1
                
    if question_count > 0:
        # Precision = TP / (TP + FP)
        # Recall = TP / (TP + FN)
        precision = tp / (tp + fp) if (tp + fp) > 0 else 0
        recall = tp / (tp + fn) if (tp + fn) > 0 else 0
        
        f1 = 2 * (precision * recall) / (precision + recall) if (precision + recall) > 0 else 0
        
        flag_score = int(f1 * 40)
        score += flag_score
        feedback.append(f"Flagging score: {flag_score}/40 (F1: {f1:.2f}, Qs found: {tp}/{question_count}).")
    elif len(topics_emails) > 0:
        # No questions existed in the set? (Unlikely with random 60 emails, but possible)
        # If no questions, ensuring 0 flags is correct
        if fp == 0:
            score += 40
            feedback.append("No questions present, correctly flagged nothing.")
        else:
            score += 20
            feedback.append("No questions present, but some items wrongly flagged.")
    else:
        feedback.append("No emails in New-Topics to verify flagging.")

    # 5. Report Sent (10 pts)
    sent_emails = result.get('sent_emails', [])
    report_found = False
    for em in sent_emails:
        to = em.get('to', '').lower()
        if 'devrel@project.org' in to:
            report_found = True
            break
    
    if report_found:
        score += 10
        feedback.append("Status report sent.")
    else:
        feedback.append("Status report not found in Sent items.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }