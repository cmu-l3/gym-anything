#!/usr/bin/env python3
"""
Verifier for vendor_communication_audit task.

Scoring Criteria:
1. Audit Folder Created (20 pts)
2. Folder Population (20 pts) - Threshold: >= 15 emails
3. Content Relevance (15 pts) - >80% of moved emails contain 'sourceforge.net'
4. Error Flagging (20 pts) - At least 3 emails flagged
5. Report Drafted (10 pts) - Draft exists to legal@company.com
6. Accuracy (15 pts) - Reported count matches actual folder count (+/- 1)

Pass Threshold: 70/100
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_vendor_communication_audit(traj, env_info, task_info):
    """
    Verify the SourceForge audit task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Extract metrics
    audit_folder_exists = result.get("audit_folder_exists", False)
    total_moved = result.get("total_moved_count", 0)
    sf_matches = result.get("sf_match_count", 0)
    flagged_count = result.get("flagged_count", 0)
    draft_exists = result.get("draft_exists", False)
    draft_recipient_correct = result.get("draft_recipient_correct", False)
    reported_count = result.get("reported_count_in_draft", 0)

    score = 0
    feedback_parts = []

    # 1. Folder Creation (20 pts)
    if audit_folder_exists:
        score += 20
        feedback_parts.append("Audit folder created.")
    else:
        feedback_parts.append("Audit folder 'Audit-SourceForge' NOT found.")

    # 2. Folder Population (20 pts)
    # Metadata expectation is 15, but we check if they moved a substantial amount
    if total_moved >= 15:
        score += 20
        feedback_parts.append(f"Folder populated with {total_moved} emails (Target: 15+).")
    elif total_moved >= 5:
        score += 10
        feedback_parts.append(f"Folder partially populated with {total_moved} emails (Target: 15+).")
    else:
        feedback_parts.append(f"Folder has too few emails ({total_moved}).")

    # 3. Content Relevance (15 pts)
    # Check if moved emails actually relate to SourceForge
    if total_moved > 0:
        relevance_ratio = sf_matches / total_moved
        if relevance_ratio >= 0.8:
            score += 15
            feedback_parts.append(f"Relevance high ({int(relevance_ratio*100)}%).")
        elif relevance_ratio >= 0.5:
            score += 7
            feedback_parts.append(f"Relevance moderate ({int(relevance_ratio*100)}%).")
        else:
            feedback_parts.append(f"Relevance low ({int(relevance_ratio*100)}% match 'sourceforge.net').")
    else:
        feedback_parts.append("No emails to check relevance.")

    # 4. Error Flagging (20 pts)
    # We expect at least 3 flags based on corpus analysis of 'failure'/'error' in SF emails
    if flagged_count >= 3:
        score += 20
        feedback_parts.append(f"Flagged {flagged_count} emails.")
    elif flagged_count >= 1:
        score += 10
        feedback_parts.append(f"Flagged {flagged_count} emails (Target: 3+).")
    else:
        feedback_parts.append("No emails flagged.")

    # 5. Report Drafted (10 pts)
    if draft_exists and draft_recipient_correct:
        score += 10
        feedback_parts.append("Report draft to 'legal@company.com' found.")
    elif draft_exists:
        score += 5
        feedback_parts.append("Draft found but recipient incorrect.")
    else:
        feedback_parts.append("No report draft found.")

    # 6. Accuracy (15 pts)
    # Does the number in the draft match the folder count?
    if draft_exists:
        diff = abs(reported_count - total_moved)
        if diff <= 1:
            score += 15
            feedback_parts.append(f"Count reported accurately (Reported: {reported_count}, Actual: {total_moved}).")
        elif diff <= 3:
            score += 5
            feedback_parts.append(f"Count slightly off (Reported: {reported_count}, Actual: {total_moved}).")
        else:
            feedback_parts.append(f"Count inaccurate (Reported: {reported_count}, Actual: {total_moved}).")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }