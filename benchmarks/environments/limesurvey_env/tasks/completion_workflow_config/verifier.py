#!/usr/bin/env python3
"""
Verifier for completion_workflow_config task.
Checks if survey settings in LimeSurvey database match the requirements.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_completion_workflow(traj, env_info, task_info):
    """
    Verify survey completion workflow settings.
    
    Required State:
    1. End Text: Contains "TechSummit 2024", "GlobalTech Solutions", "redirected"
    2. End URL: https://www.globaltechsolutions.com/techsummit2024-thankyou
    3. URL Desc: "GlobalTech Solutions Sponsor Offer" (partial match allowed)
    4. Auto-redirect: Y
    5. Admin Email: events@techsummit2024.org
    6. Save & Resume: Y
    7. Date Stamp: Y
    8. Active: Y
    """
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    settings = result.get("settings", {})
    score = 0
    feedback = []

    # 1. End Message (20 pts)
    # Check for key phrases to allow for some formatting variation
    end_text = settings.get("surveyls_endtext", "").lower()
    required_phrases = ["techsummit 2024", "globaltech solutions", "redirected"]
    phrases_found = sum(1 for p in required_phrases if p in end_text)
    
    if phrases_found == 3:
        score += 20
        feedback.append("End message correct (20/20)")
    elif phrases_found > 0:
        partial = int(20 * (phrases_found / 3))
        score += partial
        feedback.append(f"End message partial match ({phrases_found}/3 phrases) ({partial}/20)")
    else:
        feedback.append("End message missing required text (0/20)")

    # 2. End URL (15 pts)
    expected_url = "https://www.globaltechsolutions.com/techsummit2024-thankyou"
    actual_url = settings.get("surveyls_url", "").strip()
    if actual_url == expected_url:
        score += 15
        feedback.append("End URL correct (15/15)")
    elif "globaltechsolutions.com" in actual_url:
        score += 8
        feedback.append("End URL domain correct but path differs (8/15)")
    else:
        feedback.append(f"End URL incorrect: '{actual_url}' (0/15)")

    # 3. URL Description (5 pts)
    url_desc = settings.get("surveyls_urldescription", "").lower()
    if "globaltech" in url_desc and "sponsor" in url_desc:
        score += 5
        feedback.append("URL description correct (5/5)")
    elif "globaltech" in url_desc:
        score += 3
        feedback.append("URL description partial (3/5)")
    else:
        feedback.append("URL description missing/incorrect (0/5)")

    # 4. Auto-redirect (10 pts)
    if settings.get("autoredirect") == "Y":
        score += 10
        feedback.append("Auto-redirect enabled (10/10)")
    else:
        feedback.append("Auto-redirect disabled (0/10)")

    # 5. Admin Email (15 pts)
    email = settings.get("emailnotificationto", "").lower()
    if "events@techsummit2024.org" in email:
        score += 15
        feedback.append("Admin email correct (15/15)")
    else:
        feedback.append(f"Admin email incorrect: '{email}' (0/15)")

    # 6. Save and Resume (15 pts)
    if settings.get("allowsave") == "Y":
        score += 15
        feedback.append("Save and resume enabled (15/15)")
    else:
        feedback.append("Save and resume disabled (0/15)")

    # 7. Date Stamping (10 pts)
    if settings.get("datestamp") == "Y":
        score += 10
        feedback.append("Date stamping enabled (10/10)")
    else:
        feedback.append("Date stamping disabled (0/10)")

    # 8. Active (10 pts)
    if settings.get("active") == "Y":
        score += 10
        feedback.append("Survey activated (10/10)")
    else:
        feedback.append("Survey NOT active (0/10)")

    # Anti-gaming: Check timestamp logic if necessary
    # (Implicitly handled by verifying the DB state which starts at defaults)

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }