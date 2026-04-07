#!/usr/bin/env python3
"""
Verifier for Generate Class Roster PDF task.
"""

import json
import os
import tempfile
import logging
from pdfminer.high_level import extract_text

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_roster_pdf(traj, env_info, task_info):
    """
    Verify that the agent generated a valid PDF roster containing specific student names.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_file_path', '/home/ga/Documents/algebra_roster.pdf')
    expected_students = [
        metadata.get('expected_student_1', 'John Smith'),
        metadata.get('expected_student_2', 'Jane Doe')
    ]
    expected_course = metadata.get('expected_course_name', 'Algebra I')

    # 2. Retrieve JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 3. Check file existence and timestamp (Anti-Gaming)
    if not result_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file 'algebra_roster.pdf' was not found in Documents."}

    if not result_data.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not created/modified during the task window."}

    # 4. Retrieve PDF file content
    temp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
    try:
        copy_from_env(expected_path, temp_pdf.name)
        
        # 5. Analyze PDF Content
        try:
            text_content = extract_text(temp_pdf.name)
            # Normalize whitespace
            text_content = " ".join(text_content.split())
        except Exception as e:
            return {"passed": False, "score": 20, "feedback": f"File exists but is not a valid PDF or could not be read: {str(e)}"}
            
    finally:
        if os.path.exists(temp_pdf.name):
            os.unlink(temp_pdf.name)

    # 6. Scoring Logic
    score = 0
    feedback = []

    # Criterion: File Created (Base Score)
    score += 30 
    feedback.append("PDF file created successfully.")

    # Criterion: Course Name Check
    if expected_course.lower() in text_content.lower():
        score += 20
        feedback.append(f"Found course name '{expected_course}'.")
    else:
        feedback.append(f"Missing course name '{expected_course}'.")

    # Criterion: Student Names Check
    students_found = 0
    for student in expected_students:
        # Split name to allow flexible matching (e.g. "Smith, John" vs "John Smith")
        parts = student.split()
        if all(part.lower() in text_content.lower() for part in parts):
            students_found += 1
            feedback.append(f"Found student '{student}'.")
        else:
            feedback.append(f"Missing student '{student}'.")
    
    if students_found > 0:
        score += (students_found / len(expected_students)) * 50
    
    # 7. Final Assessment
    passed = score >= 65
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback)
    }