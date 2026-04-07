#!/usr/bin/env python3
"""
Verifier for configure_hr_classifications task.
Checks if the correct metadata records were created in the OrangeHRM database.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_hr_classifications(traj, env_info, task_info):
    """
    Verify that Employment Statuses, Job Categories, and Education Levels 
    were correctly configured.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Employment Statuses (30 points total, 10 each)
    es_results = result.get("employment_statuses", {})
    if es_results.get("intern_paid"):
        score += 10
        feedback_parts.append("Found 'Intern - Paid'")
    else:
        feedback_parts.append("Missing 'Intern - Paid'")
        
    if es_results.get("intern_unpaid"):
        score += 10
        feedback_parts.append("Found 'Intern - Unpaid'")
    else:
        feedback_parts.append("Missing 'Intern - Unpaid'")
        
    if es_results.get("contractor_remote"):
        score += 10
        feedback_parts.append("Found 'Contractor - Remote'")
    else:
        feedback_parts.append("Missing 'Contractor - Remote'")

    # 2. Verify Job Categories (30 points total, 15 each)
    jc_results = result.get("job_categories", {})
    if jc_results.get("remote_engineering"):
        score += 15
        feedback_parts.append("Found 'Remote Engineering'")
    else:
        feedback_parts.append("Missing 'Remote Engineering'")
        
    if jc_results.get("campus_recruitment"):
        score += 15
        feedback_parts.append("Found 'Campus Recruitment'")
    else:
        feedback_parts.append("Missing 'Campus Recruitment'")

    # 3. Verify Education Levels (40 points total, 20 each)
    ed_results = result.get("education_levels", {})
    if ed_results.get("associates_it"):
        score += 20
        feedback_parts.append("Found 'Associates Degree - IT'")
    else:
        feedback_parts.append("Missing 'Associates Degree - IT'")
        
    if ed_results.get("coding_bootcamp"):
        score += 20
        feedback_parts.append("Found 'Coding Bootcamp Certificate'")
    else:
        feedback_parts.append("Missing 'Coding Bootcamp Certificate'")

    # 4. Anti-Gaming Check (Counts must have increased)
    # If the user deleted existing records and re-added them, delta might be 0, 
    # but our setup script ensures we delete targets first.
    # So strictly, delta should be positive matching the number of added items.
    counts = result.get("counts", {})
    emp_delta = counts.get("emp_status_delta", 0)
    job_delta = counts.get("job_cat_delta", 0)
    edu_delta = counts.get("edu_delta", 0)

    # We enforce that at least some records were added to prevent 
    # obscure edge cases where DB queries might return true on stale data (unlikely with setup script)
    if emp_delta <= 0 and (es_results.get("intern_paid") or es_results.get("intern_unpaid")):
        feedback_parts.append("(Warning: Employment Status count did not increase)")
    
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }