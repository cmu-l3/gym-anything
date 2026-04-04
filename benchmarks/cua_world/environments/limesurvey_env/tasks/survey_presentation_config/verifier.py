#!/usr/bin/env python3
"""
Verifier for survey_presentation_config task.
Checks 8 specific settings in LimeSurvey database.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_survey_config(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy unavailable"}

    # Copy result
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

    settings = result.get('settings', {})
    text_content = result.get('text_content', {})
    
    # Metadata requirements
    metadata = task_info.get('metadata', {})
    req_welcome = metadata.get('required_welcome_phrases', ["TechSummit 2024", "5 minutes"])
    req_end = metadata.get('required_end_phrases', ["valuable feedback", "TechSummit 2024"])
    expected_url = metadata.get('expected_url', "https://techsummit2024.example.com/thank-you")
    
    score = 0
    feedback = []

    # 1. Welcome Message (15 pts)
    welcome_text = text_content.get('welcome', '')
    if all(phrase.lower() in welcome_text.lower() for phrase in req_welcome):
        score += 15
        feedback.append("[OK] Welcome message correct")
    else:
        feedback.append(f"[FAIL] Welcome message missing required phrases. Got length: {len(welcome_text)}")

    # 2. End Message (10 pts)
    end_text = text_content.get('endtext', '')
    if all(phrase.lower() in end_text.lower() for phrase in req_end):
        score += 10
        feedback.append("[OK] End message correct")
    else:
        feedback.append(f"[FAIL] End message missing required phrases.")

    # 3. End URL (10 pts)
    # Check for loose match (http vs https, trailing slash)
    actual_url = text_content.get('url', '').strip()
    if expected_url in actual_url or actual_url in expected_url and len(actual_url) > 10:
        score += 10
        feedback.append("[OK] End URL set")
    else:
        feedback.append(f"[FAIL] End URL mismatch: {actual_url}")

    # 4. Auto-redirect (10 pts)
    if settings.get('autoredirect') == 'Y':
        score += 10
        feedback.append("[OK] Auto-redirect enabled")
    else:
        feedback.append("[FAIL] Auto-redirect not enabled")

    # 5. Format (15 pts)
    if settings.get('format') == 'G':
        score += 15
        feedback.append("[OK] Format is Group by Group")
    else:
        feedback.append(f"[FAIL] Format incorrect: {settings.get('format')} (Expected 'G')")

    # 6. Progress Bar (15 pts)
    if settings.get('showprogress') == 'Y':
        score += 15
        feedback.append("[OK] Progress bar enabled")
    else:
        feedback.append("[FAIL] Progress bar disabled")

    # 7. Print Answers (10 pts)
    if settings.get('printanswers') == 'Y':
        score += 10
        feedback.append("[OK] Print answers enabled")
    else:
        feedback.append("[FAIL] Print answers disabled")

    # 8. Allow Previous (15 pts)
    if settings.get('allowprev') == 'Y':
        score += 15
        feedback.append("[OK] Back navigation allowed")
    else:
        feedback.append("[FAIL] Back navigation disabled")

    # Final check
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }