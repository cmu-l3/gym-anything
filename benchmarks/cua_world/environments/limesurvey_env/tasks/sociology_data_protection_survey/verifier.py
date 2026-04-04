#!/usr/bin/env python3
"""
Verifier for Sociology Data Protection Survey task.

Checks:
1. Survey existence and title (Gate)
2. Text content (IRB info, Consent, Debriefing)
3. Privacy settings (Anonymized, IP, DateStamp)
4. Presentation settings (Group-by-group, Progress bar)
5. Structure (Groups, Mandatory Consent)
6. Activation status
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sociology_data_protection_survey(traj, env_info, task_info):
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # ---------------------------------------------------------
    # SCORING LOGIC
    # ---------------------------------------------------------
    score = 0
    feedback = []
    
    # Gate Check: Survey Exists
    if not result.get("found"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No survey found. Did you create it with the correct title?"
        }

    # Gate Check: Title Match
    title = result.get("title", "")
    expected_title = "Social Media Usage and Community Belonging Study 2024"
    if expected_title.lower() not in title.lower():
        feedback.append(f"Incorrect title. Expected '{expected_title}', got '{title}'")
        # Proceed with scoring but significant penalty if needed, 
        # but usually we want to score the rest if they tried.
    else:
        score += 5 # Points for correct title (implied gate pass)
        feedback.append("Survey title correct.")

    # 1. Text Elements (30 pts)
    # Description (10)
    desc = result.get("description", "").lower()
    if "2024-soc-0847" in desc or "irb protocol" in desc:
        score += 10
        feedback.append("IRB Protocol info found in description.")
    else:
        feedback.append("Missing IRB Protocol info in description.")

    # Welcome Text (10)
    welcome = result.get("welcome_text", "").lower()
    if "informed consent" in welcome and "voluntary" in welcome:
        score += 10
        feedback.append("Informed consent language found in welcome message.")
    else:
        feedback.append("Missing 'informed consent' or 'voluntary' in welcome message.")

    # End Text (10)
    endtext = result.get("end_text", "").lower()
    if "rthorn@stateuniv.edu" in endtext and "putnam" in endtext:
        score += 10
        feedback.append("Debriefing info (email & theory) found in end message.")
    else:
        feedback.append("Missing contact email or theoretical framework (Putnam) in end message.")

    # 2. Privacy Settings (35 pts)
    settings = result.get("settings", {})
    
    # Anonymized (10)
    if settings.get("anonymized") == "Y":
        score += 10
        feedback.append("Anonymized responses enabled.")
    else:
        feedback.append("Anonymized responses NOT enabled.")

    # IP Address (10) - Should be 'N' (do NOT save)
    # LimeSurvey stores 'ipaddr' as 'Y' (save) or 'N' (don't save). Task says "Save IP address: No"
    if settings.get("ipaddr") == "N":
        score += 10
        feedback.append("IP address saving disabled.")
    else:
        feedback.append("IP address saving is enabled (should be disabled).")

    # Date Stamp (5) - Should be 'Y'
    if settings.get("datestamp") == "Y":
        score += 5
        feedback.append("Date stamp enabled.")
    else:
        feedback.append("Date stamp NOT enabled.")

    # Policy Notice (10) - Should be 1 (inline) or 2 (collapsible) -> logic checks > 0
    # The shell script exports the raw value. '0' is off.
    policy = str(settings.get("policy_notice", "0"))
    if policy != "0":
        score += 10
        feedback.append("Data policy notice enabled.")
    else:
        feedback.append("Data policy notice NOT enabled.")

    # 3. Presentation & Structure (25 pts)
    # Format (5) - 'G' for group-by-group
    if settings.get("format") == "G":
        score += 5
        feedback.append("Format is Group-by-group.")
    else:
        feedback.append(f"Format is not Group-by-group (found {settings.get('format')}).")

    # Progress Bar (5)
    if settings.get("show_progress") == "Y":
        score += 5
        feedback.append("Progress bar enabled.")
    else:
        feedback.append("Progress bar NOT enabled.")

    # Structure (10) - 3 groups
    groups = int(result.get("structure", {}).get("group_count", 0))
    if groups >= 3:
        score += 10
        feedback.append("Correct number of question groups.")
    else:
        feedback.append(f"Insufficient question groups (found {groups}, expected 3).")

    # Consent Question (5)
    if result.get("structure", {}).get("consent_question_exists"):
        score += 5
        feedback.append("Mandatory consent question found.")
    else:
        feedback.append("Mandatory consent question NOT found in a 'Consent' group.")

    # 4. Activation (5 pts)
    if settings.get("active") == "Y":
        score += 5
        feedback.append("Survey is active.")
    else:
        feedback.append("Survey is NOT active.")

    # Final Check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }