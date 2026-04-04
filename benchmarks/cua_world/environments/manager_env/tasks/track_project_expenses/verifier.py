#!/usr/bin/env python3
"""
Verifier for Track Project Expenses task.

Criteria:
1. Projects module enabled (10 pts)
2. Project 'Website Revamp' created (20 pts)
3. Expense account 'IT Services' created (10 pts)
4. Payment 1 recorded (15 pts)
5. Payment 2 recorded (15 pts)
6. Project total expense is correct (30 pts) - This proves linkage!
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_track_project_expenses(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    # 1. Projects Module Enabled (10 pts)
    if result.get("projects_module_enabled"):
        score += 10
        feedback.append("Projects module enabled.")
    else:
        feedback.append("Projects module NOT enabled.")

    # 2. Project Created (20 pts)
    if result.get("project_exists"):
        score += 20
        feedback.append("Project 'Website Revamp' found.")
    else:
        feedback.append("Project 'Website Revamp' NOT found.")

    # 3. Account Created (10 pts)
    if result.get("account_exists"):
        score += 10
        feedback.append("Account 'IT Services' found.")
    else:
        feedback.append("Account 'IT Services' NOT found.")

    # 4. Payment 1 Recorded (15 pts)
    if result.get("payment1_found"):
        score += 15
        feedback.append("Payment to TechHost Inc (150.00) found.")
    else:
        feedback.append("Payment to TechHost Inc NOT found.")

    # 5. Payment 2 Recorded (15 pts)
    if result.get("payment2_found"):
        score += 15
        feedback.append("Payment to Freelance Dev (600.00) found.")
    else:
        feedback.append("Payment to Freelance Dev NOT found.")

    # 6. Linkage Verification (30 pts)
    # The scraped page showed the project total was 750.00
    if result.get("project_total_match"):
        score += 30
        feedback.append("Project expenses total is correct (750.00).")
    else:
        feedback.append("Project expenses total is incorrect or project not found.")

    # Pass Threshold
    passed = score >= 75

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }