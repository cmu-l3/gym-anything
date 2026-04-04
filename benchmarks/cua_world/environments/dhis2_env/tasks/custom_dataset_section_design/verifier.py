#!/usr/bin/env python3
"""
Verifier for custom_dataset_section_design task.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_custom_dataset_section_design(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    # Load result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/custom_dataset_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    meta = result.get('metadata', {})
    data_entry = result.get('data_entry', {})

    # 1. Dataset Created (20 pts)
    if meta.get('found'):
        score += 20
        feedback.append("Dataset 'Vector Control Pilot 2024' created.")
    else:
        return {"passed": False, "score": 0, "feedback": "Dataset 'Vector Control Pilot 2024' not found."}

    # 2. Correct Period/OrgUnit (10 pts)
    # Check period type
    if meta.get('periodType') == 'Monthly':
        score += 5
        feedback.append("Period type is Monthly.")
    else:
        feedback.append(f"Incorrect period type: {meta.get('periodType')}")
        
    # Check Org Unit (Bo)
    if meta.get('has_bo_org_unit'):
        score += 5
        feedback.append("Assigned to Bo District.")
    else:
        feedback.append("Not assigned to Bo District.")

    # 3. Sections Created (30 pts)
    sec_count = meta.get('section_count', 0)
    if sec_count == 2:
        score += 30
        feedback.append("Exactly 2 sections created.")
    elif sec_count > 0:
        score += 15
        feedback.append(f"{sec_count} sections created (expected 2).")
    else:
        feedback.append("No sections created.")

    # 4. Section Names (10 pts)
    if meta.get('has_prevention_section') and meta.get('has_case_section'):
        score += 10
        feedback.append("Section names match requirements.")
    else:
        feedback.append(f"Section names mismatch. Found: {meta.get('section_names')}")

    # 5. Data Elements Assigned (10 pts)
    elem_count = meta.get('element_count', 0)
    if elem_count >= 4:
        score += 10
        feedback.append(f"{elem_count} Data Elements assigned.")
    elif elem_count > 0:
        score += 5
        feedback.append(f"Only {elem_count} Data Elements assigned (expected 4+).")
    else:
        feedback.append("No Data Elements assigned.")

    # 6. Test Data Entered (20 pts)
    if data_entry.get('value_entered'):
        score += 20
        feedback.append("Test data value successfully entered and verified.")
    else:
        feedback.append("No test data value found for the dataset.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }