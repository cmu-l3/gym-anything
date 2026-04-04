#!/usr/bin/env python3
"""
Verifier for Kiosk Lead Capture Setup Task.
Verifies:
1. Survey creation and activation.
2. Question structure (Name, Email, Hidden Equation Timestamp).
3. Kiosk settings (Privacy, looping, access control).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_kiosk_setup(traj, env_info, task_info):
    # 1. Setup access to result file
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Check if survey exists
    if not result.get("survey_found"):
        return {"passed": False, "score": 0, "feedback": "Survey 'TechInnovate 2026 Lead Capture' not found."}

    score = 0
    feedback = []
    
    settings = result.get("settings", {})
    questions = result.get("questions", [])
    attributes = result.get("attributes", {})

    # Criterion 1: Survey Active (10 pts)
    if settings.get("active") == "Y":
        score += 10
        feedback.append("Survey is active (+10)")
    else:
        feedback.append("Survey is NOT active")

    # Criterion 2: Questions Created (20 pts)
    # Need Name, Email, CaptureTime
    q_titles = [q.get("title", "").lower() for q in questions]
    has_name = any("name" in t for t in q_titles)
    has_email = any("email" in t for t in q_titles)
    has_time = "capturetime" in q_titles
    
    if has_name and has_email:
        score += 10
        feedback.append("Basic contact questions found (+10)")
    
    if has_time:
        score += 10
        feedback.append("CaptureTime question found (+10)")
    else:
        feedback.append("CaptureTime question missing")

    # Criterion 3: Hidden Timestamp Config (20 pts)
    # Check type is Equation ('*') and hidden attribute is set
    time_q = next((q for q in questions if q.get("title") == "CaptureTime"), None)
    if time_q:
        # Check type (Equation is usually '*' in DB, sometimes 'X' or other codes depending on version, 
        # but let's accept '*' or if text contains equation syntax)
        # We'll be lenient on type code if we can't be sure of version mapping, but strictly check hidden.
        # Actually, in modern LS, Equation type is often '*'.
        if time_q.get("type") == "*":
            score += 10
            feedback.append("CaptureTime is Equation type (+10)")
        else:
            feedback.append(f"CaptureTime type is '{time_q.get('type')}', expected Equation ('*')")

        # Check hidden attribute
        # attributes dict keys are question titles
        attr_data = attributes.get("CaptureTime")
        if attr_data and attr_data.get("attribute") == "hidden" and attr_data.get("value") == "1":
            score += 10
            feedback.append("CaptureTime is hidden (+10)")
        else:
            feedback.append("CaptureTime is NOT set to hidden")

    # Criterion 4: Privacy Settings (15 pts)
    # ipaddr='N'
    if settings.get("ipaddr") == "N":
        score += 15
        feedback.append("IP Logging disabled (+15)")
    else:
        feedback.append("IP Logging is enabled (Security Risk)")

    # Criterion 5: Access Settings (15 pts)
    # usecookie='N', allowsave='N'
    access_score = 0
    if settings.get("usecookie") == "N":
        access_score += 8
    else:
        feedback.append("Anti-spam cookie enabled (prevents reuse)")
        
    if settings.get("allowsave") == "N":
        access_score += 7
    else:
        feedback.append("Save and Resume enabled (Privacy Risk)")
        
    if access_score == 15:
        feedback.append("Kiosk access settings correct (+15)")
    else:
        feedback.append(f"Kiosk access settings partial (+{access_score})")
    score += access_score

    # Criterion 6: Kiosk Looping (20 pts)
    # autoredirect='Y' and redirect_url contains sid
    loop_score = 0
    if settings.get("autoredirect") == "Y":
        loop_score += 10
    else:
        feedback.append("Auto-redirect disabled")

    sid = settings.get("sid", "")
    url = settings.get("redirect_url", "")
    if sid and sid in url:
        loop_score += 10
        feedback.append("Redirect URL loops to survey (+10)")
    else:
        feedback.append(f"Redirect URL '{url}' does not point to survey ID {sid}")
    
    score += loop_score

    # Final check
    passed = score >= 70
    # Mandatory hard checks: Must have looping config and hidden timestamp for a "Pass" even if score is high? 
    # The prompt requirements said pass threshold 70, must include Kiosk Looping and Hidden Timestamp.
    
    # Check constraints
    looping_ok = (settings.get("autoredirect") == "Y") and (sid and sid in url)
    timestamp_ok = (time_q is not None) and (attr_data and attr_data.get("value") == "1")
    
    if not looping_ok:
        passed = False
        feedback.append("FAIL: Auto-looping is mandatory for this task.")
    
    if not timestamp_ok:
        passed = False
        feedback.append("FAIL: Hidden timestamp is mandatory.")

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }