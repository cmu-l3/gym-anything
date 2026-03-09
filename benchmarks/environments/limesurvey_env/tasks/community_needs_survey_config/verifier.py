#!/usr/bin/env python3
"""
Verifier for community_needs_survey_config task.
Verifies configuration of survey settings via database state.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_community_needs_config(traj, env_info, task_info):
    """
    Verify survey configuration.
    
    Score breakdown (Max 100):
    1. Gate: Survey exists with correct title (Required)
    2. Welcome text (keywords: Riverside, voluntary) - 10 pts
    3. End text (keywords: thank, resource/support) - 10 pts
    4. End URL (correct link) - 10 pts
    5. Presentation (Group-by-group, ProgBar, BackBtn) - 15 pts
    6. Privacy (Date=Y, IP=N, Ref=N) - 20 pts
    7. Admin Email - 10 pts
    8. Content (2+ groups, questions exist) - 10 pts
    9. Active - 15 pts
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    if not result.get("survey_found", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Survey titled 'Riverside County Community Needs Assessment 2024' not found."
        }
        
    data = result.get("survey_data", {})
    config = data.get("config", {})
    text = data.get("text", {})
    stats = data.get("stats", {})
    
    score = 0
    feedback = []
    
    # 1. Text Content Checks (Welcome/End/URL)
    # Welcome Text
    welcome = text.get("welcome", "").lower()
    if "riverside" in welcome and "voluntary" in welcome:
        score += 10
        feedback.append("Welcome text correct.")
    else:
        feedback.append("Welcome text missing required keywords (Riverside, voluntary).")
        
    # End Text
    endtext = text.get("endtext", "").lower()
    if "thank" in endtext and ("resource" in endtext or "support" in endtext):
        score += 10
        feedback.append("End text correct.")
    else:
        feedback.append("End text missing required keywords (thank, resource/support).")
        
    # End URL
    url = text.get("url", "").strip()
    if "riversidecounty.gov/community-resources" in url:
        score += 10
        feedback.append("End URL correct.")
    else:
        feedback.append(f"End URL incorrect: {url}")

    # 2. Presentation Settings (15 pts)
    # Format: G (Group by group)
    if config.get("format") == "G":
        score += 5
    else:
        feedback.append(f"Format incorrect (expected Group-by-group 'G', got '{config.get('format')}').")
        
    # Show Progress: Y
    if config.get("showprogress") == "Y":
        score += 5
    else:
        feedback.append("Progress bar not enabled.")
        
    # Allow Prev: Y
    if config.get("allowprev") == "Y":
        score += 5
    else:
        feedback.append("Back button not enabled.")

    # 3. Privacy Settings (20 pts)
    # Datestamp: Y
    if config.get("datestamp") == "Y":
        score += 5
    else:
        feedback.append("Date stamping not enabled.")
        
    # IP Addr: N (Critical)
    if config.get("ipaddr") == "N":
        score += 10
        feedback.append("IP logging disabled (Correct).")
    else:
        feedback.append("IP logging is ENABLED (Should be disabled).")
        
    # Ref URL: N
    if config.get("refurl") == "N":
        score += 5
    else:
        feedback.append("Referrer URL logging is ENABLED (Should be disabled).")

    # 4. Admin Email (10 pts)
    expected_email = "dr.martinez@riverside-sociology.edu"
    # Check all 3 possible email fields
    emails_set = [
        config.get("adminemail", ""),
        config.get("emailnotificationto", ""),
        config.get("emailresponseto", "")
    ]
    if any(expected_email in e for e in emails_set):
        score += 10
        feedback.append("Admin email configured correctly.")
    else:
        feedback.append("Admin notification email not set to Dr. Martinez.")

    # 5. Content Structure (10 pts)
    if stats.get("group_count", 0) >= 2:
        score += 5
    else:
        feedback.append(f"Insufficient groups ({stats.get('group_count')}/2).")
        
    if stats.get("groups_with_questions", 0) >= 2:
        score += 5
    else:
        feedback.append("Not all groups have questions.")

    # 6. Active Status (15 pts)
    if config.get("active") == "Y":
        score += 15
        feedback.append("Survey is active.")
    else:
        feedback.append("Survey is NOT active.")

    # Cap score at 100
    final_score = min(100, score)
    
    passed = final_score >= 70
    
    return {
        "passed": passed,
        "score": final_score,
        "feedback": " ".join(feedback)
    }