#!/usr/bin/env python3
"""
Verifier for critical_bug_thread_isolation task.

Scoring Criteria:
1. Critical-Thread folder created (10 pts)
2. Correct Bug ID identified (30 pts)
3. All messages moved to folder (20 pts)
4. Precision (No extraneous messages in folder) (20 pts)
5. Draft email created with correct info (20 pts)
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_critical_bug_thread_isolation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment error: copy unavailable"}

    # Load result from container
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

    # Load Ground Truth
    gt = result.get("ground_truth", {})
    target_bug_id = gt.get("target_bug_id", "")
    target_count = gt.get("target_count", 0)

    score = 0
    feedback = []

    # 1. Folder Creation (10 pts)
    if result.get("critical_folder_exists"):
        score += 10
        feedback.append("Folder 'Critical-Thread' exists.")
    elif result.get("found_folder_variant"):
        score += 5
        feedback.append(f"Folder exists but with wrong name: {result.get('found_folder_variant')}")
    else:
        feedback.append("Folder 'Critical-Thread' NOT found.")

    # 2. Folder Content Analysis (50 pts total)
    folder_emails = result.get("critical_folder_emails", [])
    folder_count = len(folder_emails)
    
    correct_bug_emails = 0
    incorrect_bug_emails = 0
    
    for email in folder_emails:
        subject = email.get("subject", "")
        if target_bug_id in subject:
            correct_bug_emails += 1
        else:
            incorrect_bug_emails += 1
            
    # Score: Correct identification (30 pts)
    # If the majority of emails in the folder are for the target bug, we assume correct ID found
    if folder_count > 0 and (correct_bug_emails / folder_count) > 0.5:
        score += 30
        feedback.append(f"Correctly identified Bug {target_bug_id} as the critical thread.")
    elif folder_count > 0:
        feedback.append("Folder contains mostly wrong emails.")
        
    # Score: Completeness (20 pts)
    # Did they move ALL messages?
    if correct_bug_emails >= target_count:
        score += 20
        feedback.append(f"All {target_count} messages moved successfully.")
    elif correct_bug_emails > 0:
        # Partial credit
        partial = int(20 * (correct_bug_emails / target_count))
        score += partial
        feedback.append(f"Moved {correct_bug_emails}/{target_count} messages.")

    # Score: Precision (20 pts)
    # Did they move ONLY the right messages?
    if folder_count > 0:
        if incorrect_bug_emails == 0:
            score += 20
            feedback.append("Precision perfect: No unrelated emails moved.")
        else:
            feedback.append(f"Precision error: Moved {incorrect_bug_emails} unrelated emails.")

    # 3. Draft Email (20 pts)
    draft = result.get("draft_email")
    if draft:
        draft_score = 0
        
        # Check Recipient
        if "dev-team" in draft.get("to", "").lower():
            draft_score += 5
        
        # Check Subject for Bug ID
        if target_bug_id in draft.get("subject", ""):
            draft_score += 5
        
        # Check Body for Count
        # Look for the number (target_count) in body
        # Allow +/- 1 margin of error for counting
        body_nums = re.findall(r'\d+', draft.get("body", ""))
        count_found = False
        for num in body_nums:
            if abs(int(num) - target_count) <= 1:
                count_found = True
                break
        
        if count_found:
            draft_score += 10
        
        score += draft_score
        feedback.append(f"Draft email scored {draft_score}/20 pts.")
    else:
        feedback.append("No draft email found.")

    # Final tally
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }