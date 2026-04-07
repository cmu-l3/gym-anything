#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chronological_archive_organization(traj, env_info, task_info):
    """
    Verify chronological archive organization task.
    
    Scoring Criteria:
    1. Folder Creation (25 pts): Created at least 2 monthly archive folders.
    2. Email Movement (25 pts): Moved at least 20 emails out of inbox.
    3. Sorting Accuracy (25 pts): >70% of moved emails are in the correct month folder.
    4. Report Creation (25 pts): Drafted/Sent email to records@techcorp.com with correct subject/body keywords.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    min_folders = metadata.get('min_folders', 2)
    min_emails_moved = metadata.get('min_emails_moved', 20)
    min_accuracy = metadata.get('min_accuracy_percent', 70)

    # Fetch result from environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. Verify Folders (25 pts)
    folders = result.get("folders_created", [])
    folder_count = len(folders)
    
    if folder_count >= min_folders:
        score += 25
        feedback.append(f"SUCCESS: Created {folder_count} archive folders ({', '.join(f['name'] for f in folders)}).")
    elif folder_count > 0:
        score += 10
        feedback.append(f"PARTIAL: Created {folder_count} folder (required {min_folders}).")
    else:
        feedback.append("FAIL: No archive folders created.")

    # 2. Verify Emails Moved (25 pts)
    moved_count = result.get("total_emails_moved", 0)
    
    if moved_count >= min_emails_moved:
        score += 25
        feedback.append(f"SUCCESS: Moved {moved_count} emails to archives.")
    elif moved_count > 5:
        score += 10
        feedback.append(f"PARTIAL: Moved {moved_count} emails (required {min_emails_moved}).")
    else:
        feedback.append("FAIL: Too few emails moved.")

    # 3. Verify Sorting Accuracy (25 pts)
    accuracy = result.get("sorting_accuracy", 0.0)
    
    if moved_count > 0:
        if accuracy >= min_accuracy:
            score += 25
            feedback.append(f"SUCCESS: Sorting accuracy is {accuracy:.1f}%.")
        elif accuracy >= 40:
            score += 10
            feedback.append(f"PARTIAL: Sorting accuracy is {accuracy:.1f}% (required {min_accuracy}%).")
        else:
            feedback.append(f"FAIL: Sorting accuracy {accuracy:.1f}% is too low.")
    else:
        feedback.append("SKIP: Sorting accuracy not applicable (no emails moved).")

    # 4. Verify Report (25 pts)
    report_found = result.get("draft_report_found", False) or result.get("sent_report_found", False)
    report_details = result.get("report_details", {})
    
    if report_found:
        subject = report_details.get("subject", "")
        body = report_details.get("body_snippet", "")
        
        # Check content quality
        has_keyword = "archive" in subject.lower() or "organization" in subject.lower()
        has_body_details = str(folder_count) in body or str(moved_count) in body or "folder" in body.lower()
        
        if has_keyword and has_body_details:
            score += 25
            feedback.append("SUCCESS: Confirmation email found with correct details.")
        elif has_keyword:
            score += 15
            feedback.append("PARTIAL: Confirmation email found but body content is generic.")
        else:
            score += 10
            feedback.append("PARTIAL: Email found but subject missing keywords.")
    else:
        feedback.append("FAIL: No confirmation email found in Drafts or Sent.")

    # Final result
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }