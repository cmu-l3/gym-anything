#!/usr/bin/env python3
"""
Verifier for email_campaign_conference_feedback task.

Checks:
1. Invitation, Reminder, and Confirmation email content (Subject & Body).
2. Admin and Bounce email settings.
3. Content matching against required strings/tokens.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_email_campaign(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load metadata expectations
    metadata = task_info.get("metadata", {})
    req_strings = metadata.get("required_strings", {})
    exp_admin = metadata.get("admin_email", "")
    exp_bounce = metadata.get("bounce_email", "")

    # Retrieve result file
    tmp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp_file.close()
    try:
        copy_from_env("/tmp/task_result.json", tmp_file.name)
        with open(tmp_file.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(tmp_file.name):
            os.unlink(tmp_file.name)

    if not result.get("found"):
        return {"passed": False, "score": 0, "feedback": "Survey not found in database."}

    score = 0
    feedback = []

    # Helper for checking content
    def check_content(actual, expected_list, name):
        if not actual:
            return 0, [f"{name} is empty."]
        
        matches = 0
        missing = []
        actual_normalized = actual.replace("&nbsp;", " ").replace("\n", " ") # Basic HTML cleaning
        
        for exp in expected_list:
            # Case sensitive for tokens like {FIRSTNAME}, insensitive for text? 
            # Description implies specific text. Let's use case-insensitive for text, sensitive for tokens if possible, 
            # but simple 'in' check is safest for now. Let's try case-insensitive for everything except tokens.
            
            # Simple approach: Check if expected string is in actual string
            if exp in actual_normalized or exp in actual: 
                matches += 1
            else:
                missing.append(exp)
        
        local_score = 0
        if len(expected_list) > 0:
            local_score = (matches / len(expected_list)) 
        
        return local_score, missing

    # 1. Invitation Email (35 pts total)
    # Subject (15)
    inv_subj_score, missing_subj = check_content(result["invite"]["subject"], req_strings["invite_subject"], "Invite Subject")
    score += inv_subj_score * 15
    if missing_subj: feedback.append(f"Invite Subject missing: {missing_subj}")

    # Body (20)
    inv_body_score, missing_body = check_content(result["invite"]["body"], req_strings["invite_body"], "Invite Body")
    score += inv_body_score * 20
    if missing_body: feedback.append(f"Invite Body missing: {missing_body}")


    # 2. Reminder Email (30 pts total)
    # Subject (15)
    rem_subj_score, missing_rem_subj = check_content(result["reminder"]["subject"], req_strings["remind_subject"], "Reminder Subject")
    score += rem_subj_score * 15
    if missing_rem_subj: feedback.append(f"Reminder Subject missing: {missing_rem_subj}")

    # Body (15)
    rem_body_score, missing_rem_body = check_content(result["reminder"]["body"], req_strings["remind_body"], "Reminder Body")
    score += rem_body_score * 15
    if missing_rem_body: feedback.append(f"Reminder Body missing: {missing_rem_body}")


    # 3. Confirmation Email (20 pts total)
    # Subject (10)
    conf_subj_score, missing_conf_subj = check_content(result["confirmation"]["subject"], req_strings["confirm_subject"], "Confirm Subject")
    score += conf_subj_score * 10
    if missing_conf_subj: feedback.append(f"Confirm Subject missing: {missing_conf_subj}")

    # Body (10)
    conf_body_score, missing_conf_body = check_content(result["confirmation"]["body"], req_strings["confirm_body"], "Confirm Body")
    score += conf_body_score * 10
    if missing_conf_body: feedback.append(f"Confirm Body missing: {missing_conf_body}")


    # 4. Settings (15 pts total)
    # Admin Email (8)
    curr_admin = result["settings"]["admin_email"]
    if curr_admin and exp_admin.lower() in curr_admin.lower():
        score += 8
    else:
        feedback.append(f"Admin email incorrect. Expected: {exp_admin}, Got: {curr_admin}")

    # Bounce Email (7)
    curr_bounce = result["settings"]["bounce_email"]
    if curr_bounce and exp_bounce.lower() in curr_bounce.lower():
        score += 7
    else:
        feedback.append(f"Bounce email incorrect. Expected: {exp_bounce}, Got: {curr_bounce}")

    final_score = int(score)
    passed = final_score >= 60

    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback) if feedback else "All email configurations correct!"
    }