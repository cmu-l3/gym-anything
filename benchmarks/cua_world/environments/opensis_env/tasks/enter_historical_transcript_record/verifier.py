#!/usr/bin/env python3
import json
import os
import sys
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enter_historical_transcript_record(traj, env_info, task_info):
    """
    Verify that the historical transcript record was entered correctly.
    """
    # 1. Setup access to file from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Infrastructure Error: copy_from_env not available"
        }

    # 2. Retrieve the result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve verification data: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Validation Logic
    metadata = task_info.get('metadata', {})
    expected_course = metadata.get('target_course', 'Biology').lower()
    expected_grade = float(metadata.get('target_grade', '92'))
    expected_year = metadata.get('target_year', '2023-2024')
    
    score = 0
    feedback = []
    
    # Check if record was found
    if not result.get('record_found', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No transcript record for Biology found for student Leo Vance."
        }
    
    score += 40
    feedback.append("Transcript record created.")

    details = result.get('record_details', {})
    
    # Verify Course Name (20 pts)
    actual_course = details.get('course_name', '').lower()
    if expected_course in actual_course:
        score += 20
        feedback.append(f"Course name correct ('{details.get('course_name')}').")
    else:
        feedback.append(f"Course name mismatch. Expected '{expected_course}', got '{actual_course}'.")

    # Verify Grade (20 pts)
    # Handle potentially string input "92.00" vs "92"
    try:
        actual_grade = float(details.get('grade_percent', 0))
        if abs(actual_grade - expected_grade) < 0.1:
            score += 20
            feedback.append(f"Grade correct ({actual_grade}).")
        else:
            feedback.append(f"Grade mismatch. Expected {expected_grade}, got {actual_grade}.")
    except ValueError:
        feedback.append("Could not parse grade value.")

    # Verify Year (10 pts)
    actual_year = str(details.get('school_year', ''))
    # OpenSIS might store year as int (2023) or string ("2023-2024"). 
    # The setup uses school_year_id or similar often, but our SQL extraction tried to get text.
    # We'll check if our target year string is part of it.
    if expected_year in actual_year or actual_year == "2023": 
        # "2023" often represents the start of 2023-2024 in some schemas, 
        # or the end year depending on config. We'll be lenient if it matches part.
        score += 10
        feedback.append(f"School year correct ({actual_year}).")
    else:
        feedback.append(f"School year mismatch. Expected '{expected_year}', got '{actual_year}'.")

    # Verify Credit (10 pts)
    try:
        actual_credit = float(details.get('credit', 0))
        if abs(actual_credit - 1.0) < 0.1:
            score += 10
            feedback.append("Credit value correct.")
        else:
            feedback.append(f"Credit mismatch. Expected 1.0, got {actual_credit}.")
    except ValueError:
        feedback.append("Could not parse credit value.")

    # Final Pass/Fail
    passed = (score >= 80) # Requires record exists + course + grade correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }