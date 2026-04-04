#!/usr/bin/env python3
"""
Verifier for team_user_permissions task.
Checks if survey created, users created, and permissions assigned correctly.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_team_user_permissions(traj, env_info, task_info):
    """
    Verifies:
    1. Survey 'Consumer Brand Perception Study Q4 2024' exists (15 pts)
    2. Survey has content (Group + >=2 Questions) (15 pts)
    3. User j.martinez exists (15 pts)
    4. User r.nakamura exists (15 pts)
    5. j.martinez has read responses permission (20 pts)
    6. r.nakamura has read responses permission (20 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed (copy unavailable)"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Check Survey
    survey = result.get("survey", {})
    if survey.get("found"):
        score += 15
        feedback.append("Survey created successfully.")
        
        # Check Title content (fuzzy match handled in export, verify exactness here if needed)
        title = survey.get("title", "")
        if "Consumer Brand Perception" not in title:
             feedback.append(f"Warning: Title '{title}' might be incorrect.")
        
        # Check Content
        qc = survey.get("question_count", 0)
        gc = survey.get("group_count", 0)
        if gc >= 1 and qc >= 2:
            score += 15
            feedback.append(f"Survey content verified ({gc} groups, {qc} questions).")
        else:
            feedback.append(f"Survey content incomplete ({gc} groups, {qc} questions). Expected >=1 group and >=2 questions.")
    else:
        feedback.append("Survey 'Consumer Brand Perception Study Q4 2024' NOT found.")

    # Check Users & Permissions
    users = result.get("users", {})
    
    # Julia
    jm = users.get("j_martinez", {})
    if jm.get("found"):
        score += 15
        feedback.append("User j.martinez created.")
        if jm.get("perm_response_read"):
            score += 20
            feedback.append("j.martinez has correct read permissions.")
        else:
            feedback.append("j.martinez missing 'read responses' permission.")
    else:
        feedback.append("User j.martinez NOT found.")

    # Ryo
    rn = users.get("r_nakamura", {})
    if rn.get("found"):
        score += 15
        feedback.append("User r.nakamura created.")
        if rn.get("perm_response_read"):
            score += 20
            feedback.append("r.nakamura has correct read permissions.")
        else:
            feedback.append("r.nakamura missing 'read responses' permission.")
    else:
        feedback.append("User r.nakamura NOT found.")

    # Anti-gaming check (Timestamps)
    # The export script extracts datecreated from DB. 
    # LimeSurvey stores dates as strings "YYYY-MM-DD HH:MM:SS".
    # We rely on the export script ensuring it fetched the *latest* matching records.
    # If the user existed before task start, setup_task.sh would have deleted them.
    # So existence implies creation during task session.

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }