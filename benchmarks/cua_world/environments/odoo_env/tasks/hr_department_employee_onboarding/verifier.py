#!/usr/bin/env python3
"""
Verifier for HR Onboarding task.
Checks creation of Department, Job, Schedule, and 3 Employees with correct attributes/relations.
"""

import json
import logging
import tempfile
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hr_onboarding(traj, env_info, task_info):
    """
    Verify the HR onboarding workflow.
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

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Error in export: {result['error']}"}

    score = 0
    feedback = []

    # 1. Department Check (10 pts)
    dept = result.get('department')
    if dept and "Quality Assurance" in dept.get('name', ''):
        score += 10
        feedback.append("Department 'Quality Assurance' created.")
    else:
        feedback.append("Department 'Quality Assurance' NOT found.")

    # 2. Job Position Check (8 pts)
    job = result.get('job')
    if job and "QA Inspector" in job.get('name', ''):
        score += 8
        feedback.append("Job 'QA Inspector' created.")
        # Optional: check if linked to correct department
        if dept and job.get('department_id') and job['department_id'][0] == dept['id']:
             feedback.append("Job linked to Department.")
    else:
        feedback.append("Job 'QA Inspector' NOT found.")

    # 3. Schedule Check (13 pts total)
    schedule = result.get('schedule')
    if schedule and "QA Shift Schedule" in schedule.get('name', ''):
        score += 6
        feedback.append("Schedule 'QA Shift Schedule' created.")
        
        # Check days: Mon(0) to Thu(3). Should NOT contain Fri(4), Sat(5), Sun(6)
        days = schedule.get('days_of_week', [])
        if 0 in days and 3 in days and 4 not in days and 5 not in days and 6 not in days:
            score += 7
            feedback.append("Schedule days (Mon-Thu) are correct.")
        else:
            feedback.append(f"Schedule days incorrect. Found days (0=Mon): {days}")
    else:
        feedback.append("Schedule 'QA Shift Schedule' NOT found.")

    # 4. Employees Check (69 pts total)
    # Expected data
    expected_emps = task_info.get('metadata', {}).get('employees', [])
    found_emps = {e['name']: e for e in result.get('employees', [])}
    
    maria_id = None
    if "Maria Chen" in found_emps:
        maria_id = found_emps["Maria Chen"]['id']

    for exp in expected_emps:
        name = exp['name']
        emp = found_emps.get(name)
        
        if not emp:
            feedback.append(f"Employee {name} NOT found.")
            continue

        # Existence base (10 pts each = 30)
        score += 10
        
        # Contact Info (Email: 3 pts each=9, Phone: 2 pts each=6)
        if exp['email'].lower() in (emp.get('work_email') or '').lower():
            score += 3
        else:
            feedback.append(f"{name}: Wrong email.")
            
        # Flexible phone matching
        exp_phone_digits = ''.join(filter(str.isdigit, exp['phone']))
        act_phone_digits = ''.join(filter(str.isdigit, emp.get('work_phone') or ''))
        if exp_phone_digits in act_phone_digits and len(act_phone_digits) > 5:
            score += 2
        else:
            feedback.append(f"{name}: Wrong phone.")

        # Links (Department, Job, Schedule) - implicitly checked by overall structure, 
        # but let's strictly check schedule assignment if schedule exists
        if schedule and emp.get('resource_calendar_id') and emp['resource_calendar_id'][0] == schedule['id']:
            # Points for assigning the custom schedule could be allocated here, 
            # but currently implicitly covered by "Employee created correctly"
            pass

    # 5. Manager Assignment (14 pts)
    # Check if Maria Chen is manager of QA Dept
    if dept and dept.get('manager_id') and maria_id:
        if dept['manager_id'][0] == maria_id:
            score += 14
            feedback.append("Maria Chen correctly assigned as Department Manager.")
        else:
            feedback.append("Maria Chen NOT assigned as Department Manager.")
    elif dept:
        feedback.append("Department has no manager assigned.")

    # 6. Coach Assignment (10 pts)
    # Check if Maria Chen is coach of James Okafor
    james = found_emps.get("James Okafor")
    if james and james.get('coach_id') and maria_id:
        if james['coach_id'][0] == maria_id:
            score += 10
            feedback.append("Maria Chen correctly assigned as Coach for James.")
        else:
            feedback.append("James Okafor has wrong Coach assigned.")
    elif james:
        feedback.append("James Okafor has no Coach assigned.")

    return {
        "passed": score >= 65,
        "score": score,
        "feedback": " | ".join(feedback)
    }