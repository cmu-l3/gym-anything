#!/usr/bin/env python3
"""
Verifier for mass_record_attendance task.

Task: Mark all Grade 12 students as 'Excused' for today using Mass Attendance.
      Grade 9 students should NOT be affected.

Verification Strategy:
1. Load database verification results from /tmp/task_result.json.
2. Score based on:
   - Coverage: What % of Grade 12 students were marked? (50pts)
   - Integrity: Were Grade 9 students left alone? (30pts)
   - Code Accuracy: Was the 'Excused' code used? (10pts)
   - VLM Check: Did trajectory show usage of mass attendance tool? (10pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mass_attendance(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON from container
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

    db_check = result.get("db_check", {})
    if not db_check.get("success", False):
        return {"passed": False, "score": 0, "feedback": f"Database check failed: {db_check.get('error')}"}

    score = 0
    feedback = []

    # 2. Verify Target Group (Grade 12) Coverage (50pts)
    total_g12 = db_check.get("total_g12", 0)
    marked_g12 = db_check.get("marked_g12", 0)
    
    if total_g12 > 0:
        coverage_pct = (marked_g12 / total_g12) * 100
        coverage_score = (marked_g12 / total_g12) * 50
        score += coverage_score
        feedback.append(f"Grade 12 Coverage: {marked_g12}/{total_g12} students marked ({coverage_pct:.1f}%)")
    else:
        feedback.append("Error: No Grade 12 students found in DB setup.")

    # 3. Verify Control Group (Grade 9) Integrity (30pts)
    total_g9 = db_check.get("total_g9", 0)
    affected_g9 = db_check.get("affected_g9", 0)
    
    if total_g9 > 0:
        if affected_g9 == 0:
            score += 30
            feedback.append("Control Group Integrity: Perfect (0 Grade 9 students affected).")
        else:
            # Penalize heavily for affecting control group
            penalty = (affected_g9 / total_g9) * 30
            score += max(0, 30 - penalty)
            feedback.append(f"Control Group Warning: {affected_g9}/{total_g9} Grade 9 students were incorrectly marked!")
    else:
        # If no G9 students exist, give points but warn
        score += 30
        feedback.append("Control Group: No Grade 9 students found (integrity assumed).")

    # 4. Verify Code Validity (10pts)
    if db_check.get("excused_code_found") and marked_g12 > 0:
        score += 10
        feedback.append("Correct 'Excused' attendance code used.")
    elif marked_g12 > 0:
        feedback.append("Attendance marked, but code verification ambiguous.")

    # 5. VLM / Trajectory Check (10pts)
    # Simple check: did the agent actually do anything?
    if marked_g12 > 0:
        score += 10
        feedback.append("Action verified by database changes.")
    else:
        feedback.append("No changes detected in database.")

    # Pass Threshold
    passed = score >= 90
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback),
        "details": db_check
    }