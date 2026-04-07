#!/usr/bin/env python3
"""
Verifier for conversation_thread_consolidation task.

Scoring Criteria:
1. Thread Folders Created (20 pts): At least 3 custom folders created.
2. Inbox Reduced (15 pts): Inbox count reduced by at least 10 from baseline.
3. Folders Populated (15 pts): At least 3 folders have 2+ emails each.
4. Thread Coherence (20 pts): Emails in folders actually belong together (subject similarity).
5. Summary Report (30 pts): Email drafted/sent to correct recipient with relevant content.

Pass Threshold: 60/100
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_conversation_thread_consolidation(traj, env_info, task_info):
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    summary_recipient = metadata.get('summary_recipient', 'team-leads@consultancy.org')
    
    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # --- Criterion 1: Folders Created (20 pts) ---
    custom_folders = result.get('custom_folders', {})
    folder_count = len(custom_folders)
    
    if folder_count >= 3:
        score += 20
        feedback.append(f"✓ Created {folder_count} custom folders (target: 3+)")
    elif folder_count >= 1:
        score += 10
        feedback.append(f"⚠ Created only {folder_count} custom folders (target: 3+)")
    else:
        feedback.append("✗ No custom folders created")

    # --- Criterion 2: Inbox Reduction (15 pts) ---
    reduction = result.get('inbox_reduction', 0)
    if reduction >= 10:
        score += 15
        feedback.append(f"✓ Inbox reduced by {reduction} emails")
    elif reduction >= 5:
        score += 8
        feedback.append(f"⚠ Inbox reduced by only {reduction} emails (target: 10+)")
    else:
        feedback.append(f"✗ Inbox barely changed (reduction: {reduction})")

    # --- Criterion 3: Folders Populated (15 pts) ---
    # Count how many folders have >= 2 emails
    populated_folders = sum(1 for f in custom_folders.values() if f.get('count', 0) >= 2)
    
    if populated_folders >= 3:
        score += 15
        feedback.append(f"✓ {populated_folders} folders populated with 2+ emails")
    elif populated_folders >= 1:
        score += 8
        feedback.append(f"⚠ Only {populated_folders} folders populated (target: 3+)")
    else:
        feedback.append("✗ Folders are empty or contain singletons")

    # --- Criterion 4: Thread Coherence (20 pts) ---
    # Python export script pre-calculates 'coherent' boolean for each folder
    coherent_count = result.get('coherent_folders_count', 0)
    
    if coherent_count >= 3:
        score += 20
        feedback.append(f"✓ {coherent_count} folders show strong thread coherence")
    elif coherent_count >= 1:
        score += 10
        feedback.append(f"⚠ Only {coherent_count} folders show coherence (target: 3+)")
    else:
        feedback.append("✗ No folders appear to contain coherent threads (random grouping?)")

    # --- Criterion 5: Summary Report (30 pts) ---
    drafts = result.get('drafts', [])
    sent = result.get('sent', [])
    all_msgs = drafts + sent
    
    report_found = False
    report_score = 0
    
    for msg in all_msgs:
        to_field = msg.get('to', '').lower()
        subject = msg.get('subject', '').lower()
        body = msg.get('body', '').lower()
        
        if summary_recipient in to_field:
            report_found = True
            report_score += 10 # Base points for existing
            
            # Content checks
            if 'thread' in subject or 'organiz' in subject or 'report' in subject:
                report_score += 5
                
            # Check for mention of specific folder names in body
            folder_mentions = 0
            for fname in custom_folders.keys():
                if fname.lower() in body:
                    folder_mentions += 1
            
            if folder_mentions > 0:
                report_score += 10
            
            # Check for numeric counts
            if any(char.isdigit() for char in body):
                report_score += 5
                
            break
            
    score += report_score
    if report_found:
        feedback.append(f"✓ Summary report found (Score: {report_score}/30)")
    else:
        feedback.append("✗ Summary report not found")

    # Final Result
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }