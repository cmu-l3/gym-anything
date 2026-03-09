#!/usr/bin/env python3
"""
Verifier for Survey Copy Adaptation Task
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_survey_copy_adaptation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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

    score = 0
    feedback = []

    # 1. Original Survey Preserved (5 pts)
    # The SQL count returns 1 if it exists, 0 if not (or string '1'/'0')
    orig_preserved = int(result.get("original_preserved", 0))
    if orig_preserved > 0:
        score += 5
        feedback.append("Original survey preserved.")
    else:
        feedback.append("Original survey was deleted or modified (fail).")

    # 2. New Survey Exists with Correct Title (20 pts)
    if result.get("new_survey_found"):
        score += 20
        feedback.append("New survey found with correct title.")
    else:
        feedback.append("New survey with title 'Healthcare Innovation Summit 2025 Feedback' not found.")
        # Stop here if main objective failed
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # 3. Description Updated (10 pts)
    desc = result.get("description", "")
    if "Healthcare Innovation Summit" in desc and "Boston" in desc:
        score += 10
        feedback.append("Description updated correctly.")
    else:
        feedback.append("Description missing keywords (Healthcare Innovation Summit, Boston).")

    # 4. Welcome Message Updated (10 pts)
    welcome = result.get("welcome_text", "")
    if "Healthcare Innovation Summit 2025" in welcome and "future programming" in welcome:
        score += 10
        feedback.append("Welcome message updated correctly.")
    else:
        feedback.append("Welcome message missing keywords.")

    # 5. Expiration Date Set (15 pts)
    expires = result.get("expiration", "")
    # Format from DB is usually "YYYY-MM-DD HH:MM:SS" or just date
    if expires and "2025-12-31" in str(expires):
        score += 15
        feedback.append("Expiration date set to 2025-12-31.")
    else:
        feedback.append(f"Expiration date incorrect: {expires}")

    # 6. Clinical Innovation Track Group (15 pts)
    if result.get("group_added"):
        score += 15
        feedback.append("Question group 'Clinical Innovation Track' added.")
    else:
        feedback.append("New question group not found.")

    # 7. ClinicalRelevance Question Added (15 pts)
    if result.get("question_added"):
        score += 15
        feedback.append("Question 'ClinicalRelevance' added.")
        
        # Bonus check for text content (implicit in question_added logic in export, but good to verify)
        q_text = result.get("question_text", "")
        if "relevant" in q_text.lower():
             feedback.append("Question text looks correct.")
    else:
        feedback.append("New question with code 'ClinicalRelevance' not found.")

    # 8. Survey Activated (10 pts)
    active = result.get("active", "N")
    if active == "Y":
        score += 10
        feedback.append("Survey is active.")
    else:
        feedback.append("Survey is NOT active.")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }