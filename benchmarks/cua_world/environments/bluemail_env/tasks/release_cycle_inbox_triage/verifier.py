#!/usr/bin/env python3
import json
import os
import tempfile

def verify_release_cycle_inbox_triage(traj, env_info, task_info):
    """
    Verifies the release_cycle_inbox_triage task.
    
    Criteria:
    1. Folders 'Dev-High-Priority' and 'User-Community' exist (10 pts)
    2. Sorting accuracy for Dev folder (25 pts)
    3. Sorting accuracy for User folder (15 pts)
    4. Flagging critical emails in Dev folder (20 pts)
    5. Report email existence and subject (15 pts)
    6. Report content accuracy (count matches flags) (15 pts)
    """
    
    # 1. Retrieve result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}
    
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

    # Criterion 1: Folders Created (10 pts)
    if result.get("dev_folder_exists") and result.get("user_folder_exists"):
        score += 10
        feedback.append("Both required folders created.")
    else:
        feedback.append("Failed to create both 'Dev-High-Priority' and 'User-Community' folders.")

    # Criterion 2: Dev Sorting Accuracy (25 pts)
    # Allow small margin of error (max 2 wrong)
    dev_correct = result.get("dev_sort_correct", 0)
    dev_wrong = result.get("dev_sort_wrong", 0)
    if dev_correct > 0 and dev_wrong <= 2:
        score += 25
        feedback.append(f"Dev folder sorting accurate ({dev_correct} correct).")
    elif dev_correct > 0:
        score += 10
        feedback.append(f"Dev folder sorting partial ({dev_correct} correct, {dev_wrong} wrong).")
    else:
        feedback.append("Dev folder empty or incorrect.")

    # Criterion 3: User Sorting Accuracy (15 pts)
    user_correct = result.get("user_sort_correct", 0)
    user_wrong = result.get("user_sort_wrong", 0)
    if user_correct > 0 and user_wrong <= 2:
        score += 15
        feedback.append(f"User folder sorting accurate ({user_correct} correct).")
    elif user_correct > 0:
        score += 5
        feedback.append(f"User folder sorting partial ({user_correct} correct, {user_wrong} wrong).")
    else:
        feedback.append("User folder empty or incorrect.")

    # Criterion 4: Priority Flagging (20 pts)
    # Check if flags exist in Dev folder
    flagged = result.get("flagged_count", 0)
    flagged_content_match = result.get("flagged_correctly_content", 0)
    
    if flagged >= 3:
        if flagged_content_match >= 3:
            score += 20
            feedback.append(f"Correctly flagged {flagged} priority emails.")
        else:
            score += 10
            feedback.append(f"Flagged {flagged} emails, but content match analysis was weak.")
    elif flagged > 0:
        score += 5
        feedback.append(f"Only flagged {flagged} emails (expected 3+).")
    else:
        feedback.append("No emails were flagged in the Dev folder.")

    # Criterion 5: Report Drafted (15 pts)
    if result.get("report_found"):
        if result.get("report_subject_ok"):
            score += 15
            feedback.append("Report email found with correct subject.")
        else:
            score += 10
            feedback.append("Report email found but subject incorrect.")
    else:
        feedback.append("No report email found sent to council@apache.org.")

    # Criterion 6: Report Accuracy (15 pts)
    # Compare reported count vs actual flagged count
    reported_count = result.get("reported_count", -1)
    if reported_count != -1:
        # Allow +/- 1 tolerance
        if abs(reported_count - flagged) <= 1:
            score += 15
            feedback.append(f"Reported count ({reported_count}) matches flagged count ({flagged}).")
        else:
            feedback.append(f"Reported count ({reported_count}) does not match actual flagged count ({flagged}).")
    else:
        feedback.append("Could not identify a number in the report body.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }