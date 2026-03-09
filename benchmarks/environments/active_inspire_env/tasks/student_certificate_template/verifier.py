#!/usr/bin/env python3
"""
Verifier for student_certificate_template task.

Scoring (100 points, pass at 70):
  1. File Validity (20 pts): Exists, valid format, created during task.
  2. Text Content (30 pts):
     - Title "Student of the Month" (15 pts)
     - Fields: "Awarded to", "Date", "Signed/Teacher" (5 pts each)
  3. Structural Layout (35 pts):
     - Border (Rectangle) present (15 pts)
     - Lines for writing (at least 3) (20 pts)
  4. Decoration (15 pts):
     - At least 2 Star/Circle shapes
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_student_certificate(traj, env_info, task_info):
    """
    Verify the student certificate template.
    Checks for file existence, specific text fields, and shape elements.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No copy_from_env function available"
        }

    # Read the exported result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()
        try:
            copy_from_env('/tmp/task_result.json', tmp_path)
            with open(tmp_path, 'r', encoding='utf-8-sig') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read export result: {e}"
        }

    score = 0
    feedback_parts = []
    
    # Gate check
    if not result.get('file_found'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Certificate file not found."
        }

    # 1. File Validity (20 pts)
    file_valid = result.get('file_valid', False)
    created_during = result.get('created_during_task', False)
    
    if file_valid and created_during:
        score += 20
        feedback_parts.append("Valid file created during task (20/20)")
    elif file_valid:
        score += 10
        feedback_parts.append("File valid but timestamp check failed (10/20)")
    else:
        feedback_parts.append("File invalid format (0/20)")

    # 2. Text Content (30 pts)
    # Title
    if result.get('has_title', False):
        score += 15
        feedback_parts.append("Title present (15/15)")
    else:
        feedback_parts.append("Title missing (0/15)")
        
    # Fields
    field_points = 0
    if result.get('has_awarded', False): field_points += 5
    if result.get('has_date', False): field_points += 5
    if result.get('has_signed', False): field_points += 5
    
    score += field_points
    if field_points == 15:
        feedback_parts.append("All form fields present (15/15)")
    else:
        feedback_parts.append(f"Some form fields missing ({field_points}/15)")

    # 3. Structural Layout (35 pts)
    # Border (Rectangle)
    rect_count = result.get('rect_count', 0)
    # Also check total shapes in case detection is fuzzy, but require at least some structure
    total_shapes = result.get('total_shape_count', 0)
    
    if rect_count >= 1 or (total_shapes >= 5 and rect_count == 0):
        # Allow generic shape count fallback if specific rect tag missed but many shapes present
        score += 15
        feedback_parts.append("Border/Rectangle detected (15/15)")
    else:
        feedback_parts.append("No border rectangle detected (0/15)")

    # Lines
    line_count = result.get('line_count', 0)
    if line_count >= 3:
        score += 20
        feedback_parts.append(f"Writing lines detected: {line_count} (20/20)")
    elif line_count > 0:
        score += 10
        feedback_parts.append(f"Insufficient lines: {line_count}/3 (10/20)")
    else:
        feedback_parts.append("No lines detected (0/20)")

    # 4. Decoration (15 pts)
    star_circle = result.get('star_circle_count', 0)
    if star_circle >= 2:
        score += 15
        feedback_parts.append("Decorations present (15/15)")
    elif star_circle == 1:
        score += 5
        feedback_parts.append("One decoration found (5/15)")
    else:
        feedback_parts.append("No specific decorations found (0/15)")

    passed = score >= 70 and result.get('has_title', False) and file_valid

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }