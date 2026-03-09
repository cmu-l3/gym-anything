#!/usr/bin/env python3
"""
Verifier for Geometry Exit Ticket task.

Verification Criteria (100 points total, Pass >= 70):
1. File Validation (15 pts): File exists, valid format, created during task.
2. Structure (10 pts): Exactly 5 pages.
3. Text Content (45 pts):
   - Title "Exit Ticket" (10)
   - Teacher "Rivera" (5)
   - "Acute" (10)
   - "Right" (10)
   - "Obtuse" (10)
4. Drawing Content (20 pts):
   - Lines for angles >= 4 lines (10) (Each angle needs 2 lines, but allowing for one continuous polyline or minimal effort)
   - Circles for self-assess >= 3 (10)
5. Self-Assessment Text (10 pts): Presence of self-assessment prompts.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_geometry_exit_ticket(traj, env_info, task_info):
    """
    Verify the geometry exit ticket flipchart creation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()
        try:
            copy_from_env('/tmp/task_result.json', tmp_path)
            with open(tmp_path, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load verification result: {str(e)}"
        }

    score = 0
    feedback = []
    
    # 1. File Validation (15 pts)
    if result.get('file_found', False) and result.get('file_valid', False):
        if result.get('created_during_task', False):
            score += 15
            feedback.append("File created successfully (15/15)")
        else:
            score += 5
            feedback.append("File exists but timestamp pre-dates task (5/15)")
    else:
        feedback.append("File not found or invalid format (0/15)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Structure (10 pts)
    page_count = result.get('page_count', 0)
    if page_count == 5:
        score += 10
        feedback.append("Correct page count (5) (10/10)")
    elif page_count >= 3:
        score += 5
        feedback.append(f"Page count {page_count}/5 (5/10)")
    else:
        feedback.append(f"Insufficient pages: {page_count} (0/10)")

    # 3. Text Content (45 pts)
    text_checks = [
        ('has_title_text', "Exit Ticket", 10),
        ('has_teacher_name', "Rivera", 5),
        ('has_acute', "Acute", 10),
        ('has_right', "Right", 10),
        ('has_obtuse', "Obtuse", 10)
    ]
    
    for key, label, pts in text_checks:
        if result.get(key, False):
            score += pts
            feedback.append(f"Found '{label}' ({pts}/{pts})")
        else:
            feedback.append(f"Missing '{label}' (0/{pts})")

    # 4. Drawing Content (20 pts)
    # Lines: Expecting 3 angles x 2 lines = 6 lines. 
    # Threshold set to 4 to allow for some polyline usage or partial completion.
    line_count = result.get('line_count', 0)
    if line_count >= 4:
        score += 10
        feedback.append(f"Angle drawings detected ({line_count} lines) (10/10)")
    else:
        feedback.append(f"Insufficient angle drawings ({line_count} lines found, need 4+) (0/10)")

    # Circles: Expecting 3 circles.
    circle_count = result.get('circle_count', 0)
    if circle_count >= 3:
        score += 10
        feedback.append(f"Self-assessment circles detected ({circle_count}) (10/10)")
    elif circle_count >= 1:
        score += 5
        feedback.append(f"Partial circles detected ({circle_count}) (5/10)")
    else:
        feedback.append(f"No circles found (0/10)")

    # 5. Self-Assessment Text (10 pts)
    if result.get('has_self_assess', False):
        score += 10
        feedback.append("Self-assessment text found (10/10)")
    else:
        feedback.append("Missing self-assessment text (0/10)")

    # Final Calculation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }