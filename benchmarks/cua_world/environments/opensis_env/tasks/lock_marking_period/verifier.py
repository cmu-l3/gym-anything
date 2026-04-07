#!/usr/bin/env python3
"""
Verifier for lock_marking_period task.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_lock_marking_period(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verifies that 'Quarter 1' is locked (grades/comments = N) 
    and 'Full Year' remains open (grades = Y).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy capability missing"}

    # 1. Retrieve result data
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Analyze Marking Periods
    marking_periods = result.get("marking_periods", [])
    if not marking_periods:
        return {"passed": False, "score": 0, "feedback": "No marking period data found in database"}

    q1_status = None
    fy_status = None

    for mp in marking_periods:
        title = mp.get("title", "")
        short = mp.get("short_name", "")
        
        if title == "Quarter 1" or short == "Q1":
            q1_status = mp
        elif title == "Full Year" or short == "FY":
            fy_status = mp

    # 3. Scoring
    score = 0
    feedback = []
    passed = False

    # Check Q1 (Target)
    if q1_status:
        grades_locked = q1_status.get("does_grades") == "N"
        comments_locked = q1_status.get("does_comments") == "N"
        
        if grades_locked:
            score += 40
            feedback.append("Quarter 1 grades successfully locked.")
        else:
            feedback.append("Quarter 1 grades are still OPEN (expected locked/unchecked).")
            
        if comments_locked:
            score += 30
            feedback.append("Quarter 1 comments successfully locked.")
        else:
            feedback.append("Quarter 1 comments are still OPEN (expected locked/unchecked).")
    else:
        feedback.append("Critical Error: 'Quarter 1' record not found in database.")

    # Check FY (Control)
    if fy_status:
        grades_open = fy_status.get("does_grades") == "Y"
        # We focus on grades for the control check, comments usually follow
        if grades_open:
            score += 30
            feedback.append("Full Year correctly remains open.")
        else:
            feedback.append("Warning: 'Full Year' was accidentally locked.")
    else:
        feedback.append("Critical Error: 'Full Year' record not found in database.")

    # 4. Anti-gaming / Sanity Check
    # If score is high but they locked FY accidentally, we penalize heavily in logic above (missing 30 pts)
    # But pass threshold requires precision.
    
    if score >= 90:
        passed = True
    
    # 5. VLM / Trajectory check (Optional enhancement)
    # Could check if "School Setup" was visited, but DB state is the source of truth here.

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": {
            "q1_status": q1_status,
            "fy_status": fy_status
        }
    }