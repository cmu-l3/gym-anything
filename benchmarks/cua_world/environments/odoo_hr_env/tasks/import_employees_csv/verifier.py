#!/usr/bin/env python3
"""
Verifier for import_employees_csv task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_employees_csv(traj, env_info, task_info):
    """
    Verifies that employees were imported correctly from CSV.
    
    Criteria:
    1. Employee count increased by at least 5 (15 pts)
    2. Specific employees exist (10 pts each, total 50)
    3. Employee data (Department, Job Title) is correct (35 pts distributed)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected data from metadata
    metadata = task_info.get('metadata', {})
    expected_employees = metadata.get('expected_employees', [])
    
    # 1. Retrieve result JSON
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
    
    # 2. Check Odoo Accessibility
    if not result.get("odoo_accessible", False):
        return {"passed": False, "score": 0, "feedback": "Could not access Odoo database to verify results."}
        
    # 3. Check Count Increase (15 pts)
    initial_count = result.get("initial_count", 0)
    final_count = result.get("final_count", 0)
    count_diff = final_count - initial_count
    
    if count_diff >= 5:
        score += 15
        feedback_parts.append(f"Employee count increased by {count_diff} (Expected >= 5)")
    else:
        feedback_parts.append(f"Employee count only increased by {count_diff} (Expected 5)")

    # 4. Check Specific Employees (10 pts existence + 7 pts details each)
    imported_list = result.get("imported_employees", [])
    # Create a lookup map by email for easy verification
    imported_map = {emp.get("email"): emp for emp in imported_list}
    
    employees_found = 0
    details_correct = 0
    
    for expected in expected_employees:
        email = expected["email"]
        if email in imported_map:
            score += 10
            employees_found += 1
            
            # Check details
            actual = imported_map[email]
            
            # Department Check (3 pts)
            # Handle case where Odoo might have 'Sales' vs 'Sales Department' nuances, 
            # though in this env they are exact matches to demo data.
            act_dept = actual.get("department", "") or ""
            exp_dept = expected["department"]
            dept_match = exp_dept.lower() in act_dept.lower()
            
            # Job Title Check (3 pts)
            act_job = actual.get("job_title", "") or ""
            exp_job = expected["job"]
            job_match = exp_job.lower() in act_job.lower()
            
            # Name Check (1 pt)
            act_name = actual.get("name", "")
            exp_name = expected["name"]
            name_match = exp_name.lower() == act_name.lower()
            
            if dept_match and job_match and name_match:
                score += 7
                details_correct += 1
            else:
                mistakes = []
                if not dept_match: mistakes.append(f"Dept: {act_dept} vs {exp_dept}")
                if not job_match: mistakes.append(f"Job: {act_job} vs {exp_job}")
                if not name_match: mistakes.append(f"Name: {act_name} vs {exp_name}")
                feedback_parts.append(f"{expected['name']} details mismatch: {', '.join(mistakes)}")
        else:
            feedback_parts.append(f"Missing employee: {expected['name']}")

    feedback_parts.append(f"Found {employees_found}/5 employees. Details correct for {details_correct}/5.")
    
    # 5. Finalize
    passed = (score >= 60) and (employees_found >= 4)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }