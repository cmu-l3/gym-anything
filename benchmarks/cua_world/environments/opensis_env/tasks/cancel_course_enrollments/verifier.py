#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cancel_enrollments(traj, env_info, task_info):
    """
    Verify that the agent cancelled enrollments for ART-303 without deleting the course.
    """
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
    feedback_parts = []
    passed = False

    # Extract metrics
    art_enrollment = result.get("art_enrollment_count", -1)
    control_enrollment = result.get("control_enrollment_count", -1)
    section_exists = result.get("section_exists", False)
    active_students = result.get("active_student_count", 0)
    
    # Criterion 1: Target Enrollments Cleared (50 pts)
    # Ideally 0. We tolerate 0.
    if art_enrollment == 0:
        score += 50
        feedback_parts.append("Success: All students unenrolled from ART-303.")
    elif art_enrollment < 5 and art_enrollment > 0:
        score += (5 - art_enrollment) * 10  # Partial credit
        feedback_parts.append(f"Partial: {art_enrollment} students still enrolled.")
    else:
        feedback_parts.append(f"Failure: {art_enrollment} students still enrolled (expected 0).")

    # Criterion 2: Section Preserved (20 pts)
    if section_exists:
        score += 20
        feedback_parts.append("Success: Course section preserved.")
    else:
        feedback_parts.append("Failure: Course section was deleted!")

    # Criterion 3: Students Preserved & Active (15 pts)
    # We created 5 students, they should all be active
    if active_students == 5:
        score += 15
        feedback_parts.append("Success: Student records remain active.")
    else:
        feedback_parts.append(f"Warning: Only {active_students}/5 students are active.")
        score += int((active_students / 5) * 15)

    # Criterion 4: Control Courses Intact (15 pts)
    # They should still be in MATH-101 (count 5)
    if control_enrollment == 5:
        score += 15
        feedback_parts.append("Success: Control course enrollments intact.")
    elif control_enrollment > 0:
        score += int((control_enrollment / 5) * 15)
        feedback_parts.append(f"Warning: Control enrollments affected ({control_enrollment}/5).")
    elif control_enrollment == 0:
        feedback_parts.append("Failure: Students were dropped from ALL courses (including Math).")
    
    # Pass threshold
    if score >= 85:
        passed = True
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }