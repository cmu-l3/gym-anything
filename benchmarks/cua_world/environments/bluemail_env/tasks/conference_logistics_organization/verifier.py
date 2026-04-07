#!/usr/bin/env python3
import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_conference_logistics(traj, env_info, task_info):
    """
    Verifies the conference_logistics_organization task.
    
    Scoring Criteria:
    1. ILUG-Events folder created (15 pts)
    2. Categorization Accuracy (30 pts)
       - All [ILUG] emails moved to folder
       - No [ILUG] emails left in Inbox
    3. Reporting Accuracy (15 pts)
       - ilug_count.txt exists and matches actual count (+/- 1 tolerance)
    4. Forwarding Action (15 pts)
       - Email sent to travel-approvals@company.com
    5. Forwarding Precision (25 pts)
       - The forwarded email matches the most recent [ILUG] email subject
       - Body contains required text
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Folder Creation (15 pts)
    if result.get('folder_created', False):
        score += 15
        feedback.append("Folder 'ILUG-Events' created.")
    else:
        feedback.append("Failed to create 'ILUG-Events' folder.")

    # 2. Categorization Accuracy (30 pts)
    moved = result.get('moved_ilug_count', 0)
    remaining = result.get('remaining_ilug_in_inbox', 0)
    expected = result.get('expected_ilug_count', 0)
    
    # Partial credit logic
    if moved > 0:
        if remaining == 0 and moved == expected:
            score += 30
            feedback.append(f"All {moved} ILUG emails correctly moved.")
        elif remaining > 0:
            # Partial: moved some but missed some
            score += 15
            feedback.append(f"Moved {moved} ILUG emails, but {remaining} left in inbox.")
        else:
            # Maybe moved correct ones but deleted some? or extras?
            score += 20
            feedback.append(f"Moved {moved} ILUG emails (expected {expected}).")
    else:
        feedback.append("No ILUG emails were moved to the folder.")

    # 3. Reporting Accuracy (15 pts)
    reported = result.get('reported_count_value', -1)
    # Check against what was actually moved OR what was expected (lenient)
    # If they moved 5 and wrote 5, good. If they moved 4 and wrote 5 (thinking they moved 5), partial? 
    # Let's verify against what exists in the folder as the "truth" of their action
    
    if result.get('reported_count_file_exists', False):
        if abs(reported - moved) <= 1 and moved > 0:
            score += 15
            feedback.append(f"Count file correct: {reported}.")
        else:
            feedback.append(f"Count file exists but value {reported} does not match folder count {moved}.")
    else:
        feedback.append("Count file 'ilug_count.txt' not found.")

    # 4. Forwarding Action (15 pts)
    if result.get('forward_attempted', False):
        score += 15
        feedback.append("Forwarded email to travel-approvals found.")
    else:
        feedback.append("No email forwarded to travel-approvals@company.com found.")

    # 5. Forwarding Precision (25 pts)
    # Requires forward_attempted to be true
    if result.get('forward_attempted', False):
        precision_score = 0
        if result.get('forward_correct_subject', False):
            precision_score += 15
            feedback.append("Forwarded the correct email (subject match).")
        else:
            feedback.append("Forwarded email subject did not match expected target.")
            
        if result.get('forward_correct_body', False):
            precision_score += 10
            feedback.append("Forward body contained required approval text.")
        else:
            feedback.append("Forward body missing 'approve trip' text.")
            
        score += precision_score

    # Final check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }