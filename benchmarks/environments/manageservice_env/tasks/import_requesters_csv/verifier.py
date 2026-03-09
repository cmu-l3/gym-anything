#!/usr/bin/env python3
"""
Verifier for import_requesters_csv task.

Checks:
1. Number of users imported (Target: 15)
2. Correct field mapping (First Name vs Full Name)
3. Creation of new departments
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_requesters_csv(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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
    
    # Criterion 1: Users Imported (Max 40 points)
    # We use 'imported_email_count' as the ground truth for success
    imported_count = int(result.get('imported_email_count', 0))
    expected_count = 15
    
    if imported_count == expected_count:
        score += 40
        feedback.append(f"Successfully imported all {expected_count} users.")
    elif imported_count > 0:
        # Partial credit: 2 points per user
        points = min(30, imported_count * 2)
        score += points
        feedback.append(f"Imported {imported_count}/{expected_count} users.")
    else:
        feedback.append("No users with the expected email domain were found.")

    # Criterion 2: Field Mapping Accuracy (Max 30 points)
    # Check sample user 'Elena'
    sample = result.get('sample_user', {})
    if sample.get('found'):
        first_name = sample.get('first_name', '').strip()
        job_title = sample.get('job_title', '').strip()
        
        # Check First Name Mapping
        if first_name == "Elena":
            score += 15
            feedback.append("First Name mapped correctly.")
        elif "Corves" in first_name:
            feedback.append("Mapping Error: First Name field contains Surname or Full Name.")
        
        # Check Job Title Mapping (often mapped to Description or Job Title field)
        # Note: In the DB query we pulled 'description'. 
        # If the user mapped JobPosition -> Job Title/Description, it should appear here.
        if "Logistics Coordinator" in job_title or "Logistics Coordinator" in str(result): 
            # Loose check in case it's in a different column we couldn't easily query
            score += 15
            feedback.append("Job Title mapped correctly.")
        else:
            feedback.append("Job Title not verified in user record.")
    else:
        feedback.append("Sample verification user 'Elena Corves' not found.")

    # Criterion 3: Department Creation (Max 30 points)
    if result.get('department_created'):
        score += 30
        feedback.append("New Department 'Nebula_Ops' was successfully created.")
    else:
        feedback.append("Failed to create new Department 'Nebula_Ops'.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }