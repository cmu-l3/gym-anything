#!/usr/bin/env python3
"""
Verifier for public_event_registration_setup task.
Checks if the survey allows public registration, uses CAPTCHA,
and has the required custom attributes configured correctly.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_public_registration(traj, env_info, task_info):
    """
    Verify public registration setup.
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
        return {"passed": False, "score": 0, "feedback": "Survey 'Global Tech Summit 2024' not found in database."}

    score = 0
    feedback = []

    # 1. Public Registration Enabled (20 pts)
    if result.get("allow_register") == "Y":
        score += 20
        feedback.append("Public registration enabled (+20)")
    else:
        feedback.append("Public registration NOT enabled")

    # 2. CAPTCHA Enabled (20 pts)
    if result.get("use_captcha") == "Y":
        score += 20
        feedback.append("CAPTCHA enabled (+20)")
    else:
        feedback.append("CAPTCHA NOT enabled")

    # 3. Attributes Check (60 pts total)
    attributes = result.get("attributes", [])
    
    # Helper to find attribute by text match
    def find_attr(keyword):
        for a in attributes:
            # Check description (User facing label) or name (Internal DB col)
            if keyword.lower() in a.get("description", "").lower() or keyword.lower() in a.get("name", "").lower():
                return a
        return None

    # Check Organization
    org_attr = find_attr("Organization")
    if org_attr:
        score += 15
        feedback.append("'Organization' attribute found (+15)")
        if org_attr.get("show_register") == "Y":
            score += 7.5
            feedback.append("'Organization' visible on registration (+7.5)")
        else:
            feedback.append("'Organization' NOT visible on registration")
        
        if org_attr.get("mandatory") == "Y":
            score += 7.5
            feedback.append("'Organization' is mandatory (+7.5)")
        else:
            feedback.append("'Organization' is NOT mandatory")
    else:
        feedback.append("'Organization' attribute missing")

    # Check Job Title
    job_attr = find_attr("Job")  # keyword "Job" matches "Job Title"
    if job_attr:
        score += 15
        feedback.append("'Job Title' attribute found (+15)")
        if job_attr.get("show_register") == "Y":
            score += 7.5
            feedback.append("'Job Title' visible on registration (+7.5)")
        else:
            feedback.append("'Job Title' NOT visible on registration")
        
        if job_attr.get("mandatory") == "Y":
            score += 7.5
            feedback.append("'Job Title' is mandatory (+7.5)")
        else:
            feedback.append("'Job Title' is NOT mandatory")
    else:
        feedback.append("'Job Title' attribute missing")

    # Threshold
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }