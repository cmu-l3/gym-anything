#!/usr/bin/env python3
"""
Verifier for product_concept_survey_config task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_product_concept_config(traj, env_info, task_info):
    """
    Verify survey configuration settings.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if not result.get("survey_found"):
        return {"passed": False, "score": 0, "feedback": "Survey 'Sparkling Water Concept Test - Wave 3' not found."}

    settings = result.get("settings", {})
    text = result.get("text", {})
    
    score = 0
    feedback = []

    # 1. Format: Question by Question ('S') (12 pts)
    if settings.get("format") == "S":
        score += 12
    else:
        feedback.append(f"Format incorrect: expected 'Question by Question' (S), got '{settings.get('format')}'")

    # 2. Progress Bar: Yes ('Y') (10 pts)
    if settings.get("showprogress") == "Y":
        score += 10
    else:
        feedback.append("Progress bar not enabled")

    # 3. Allow Previous: No ('N') (12 pts)
    if settings.get("allowprev") == "N":
        score += 12
    else:
        feedback.append("Back button (Previous) not disabled")

    # 4. Show No Answer: No ('N') (10 pts)
    if settings.get("shownoanswer") == "N":
        score += 10
    else:
        feedback.append("'No answer' option not hidden")

    # 5. Admin Notification Email (12 pts)
    expected_email = "concept-alerts@beverageco.com"
    actual_email = settings.get("emailnotificationto", "") or ""
    if expected_email in actual_email:
        score += 12
    else:
        feedback.append(f"Admin notification email incorrect. Expected '{expected_email}', got '{actual_email}'")

    # 6. Start Date: Feb 1 2025 (5 pts)
    start_date = settings.get("startdate", "") or ""
    if "2025-02-01" in start_date:
        score += 5
    else:
        feedback.append(f"Start date incorrect. Expected '2025-02-01', got '{start_date}'")

    # 7. Expiry Date: Mar 15 2025 (4 pts)
    expires = settings.get("expires", "") or ""
    if "2025-03-15" in expires:
        score += 4
    else:
        feedback.append(f"Expiry date incorrect. Expected '2025-03-15', got '{expires}'")

    # 8. Welcome Text (15 pts)
    welcome = text.get("welcometext", "") or ""
    # Check for key phrases to ignore HTML tags
    if "Sparkling Water Concept Evaluation" in welcome and "7 minutes" in welcome:
        score += 15
    else:
        feedback.append("Welcome message text missing key phrases")

    # 9. End Text (10 pts)
    end_msg = text.get("endtext", "") or ""
    if "concept evaluation" in end_msg and "product development decisions" in end_msg:
        score += 10
    else:
        feedback.append("End message text missing key phrases")

    # 10. End URL (10 pts)
    url = text.get("url", "") or ""
    if "panel.researchportal.com/complete" in url:
        score += 10
    else:
        feedback.append("End URL incorrect")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback) if feedback else "All configuration settings correct!"
    }