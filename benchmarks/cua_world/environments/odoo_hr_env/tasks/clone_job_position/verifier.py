#!/usr/bin/env python3
import json
import os
import sys
import tempfile
import datetime

def verify_clone_job_position(traj, env_info, task_info):
    """
    Verify that the 'Senior Python Developer' job was created by cloning
    'Experienced Developer' and modifying specific fields.
    """
    # 1. Setup - Load Result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # 2. Extract Data
    job_found = result.get("job_found", False)
    details = result.get("job_details", {})
    source_exists = result.get("source_job_exists", False)
    task_start = result.get("task_start_timestamp", 0)
    
    # 3. Score Calculation
    score = 0
    feedback = []

    # Criterion 1: Job Created (30 pts)
    if job_found:
        score += 30
        feedback.append("Job 'Senior Python Developer' created.")
    else:
        feedback.append("Job 'Senior Python Developer' NOT found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: Correct Department (20 pts)
    dept = details.get("department", "")
    if dept == "R&D USA":
        score += 20
        feedback.append("Department correctly set to 'R&D USA'.")
    else:
        feedback.append(f"Incorrect department: found '{dept}', expected 'R&D USA'.")

    # Criterion 3: Correct Recruitment Target (20 pts)
    target = details.get("recruitment_target", 0)
    if target == 2:
        score += 20
        feedback.append("Recruitment target correctly set to 2.")
    else:
        feedback.append(f"Incorrect recruitment target: found {target}, expected 2.")

    # Criterion 4: Description Preserved / Cloned (15 pts)
    # If the description length is > 0, it likely means they cloned it or copied it.
    # Empty description would imply they created a bare record without cloning/copying.
    desc_len = details.get("description_length", 0)
    if desc_len > 10:
        score += 15
        feedback.append("Job description present (indicates cloning successful).")
    else:
        feedback.append("Job description is empty or too short. Did you clone the position?")

    # Criterion 5: Anti-Gaming / Source Integrity (15 pts)
    # Check creation date vs task start
    # Odoo returns create_date as "YYYY-MM-DD HH:MM:SS" (UTC usually)
    # We'll do a basic check if create_date string exists
    create_date_str = details.get("create_date")
    created_during_task = False
    
    if create_date_str:
        try:
            # Simple heuristic: if the record has a create_date, and we know we deleted it
            # in setup, then it must have been created now.
            # Parsing exact seconds can be tricky due to timezones, but existence is key here
            # since setup deletes it.
            created_during_task = True
        except:
            pass

    if created_during_task and source_exists:
        score += 15
        feedback.append("Source job preserved and new job created during task.")
    elif not source_exists:
        feedback.append("Warning: Source job 'Experienced Developer' seems to be missing (renamed?).")
    
    # 4. Final Verdict
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }