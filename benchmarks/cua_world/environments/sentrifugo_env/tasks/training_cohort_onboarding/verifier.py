#!/usr/bin/env python3
"""
Verifier for training_cohort_onboarding task.

Verifies:
1. "Training Coordinator" job title created
2. 3 employees created (Amara, Rajesh, Sofia)
3. For each employee, verifies 8 specific fields matching the instructions

Uses copy_from_env to securely fetch the database state extracted by export_result.sh.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def safe_lower(val):
    return str(val).strip().lower() if val else ""


def verify_training_cohort_onboarding(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve expected values and scoring
    metadata = task_info.get('metadata', {})
    expected_employees = metadata.get('employees', [])
    scoring = metadata.get('scoring', {})
    breakdown = scoring.get('breakdown', {})
    pass_threshold = metadata.get('pass_threshold', 60)

    score = 0
    feedback_parts = []

    # Copy and parse result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            db_state = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported state: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Prepare lookup dictionaries
    dept_lookup = {d['id']: d['deptname'] for d in db_state.get('departments_lookup', [])}
    title_lookup = {t['id']: t['jobtitlename'] for t in db_state.get('jobtitles_lookup', [])}
    mgr_lookup = {m['id']: m['employeeId'] for m in db_state.get('manager_lookup', [])}

    # 1. Verify Job Title Creation
    job_titles = db_state.get('job_titles', [])
    active_tc = [jt for jt in job_titles if jt.get('isactive') == '1']
    if active_tc:
        score += scoring.get('job_title', 10)
        feedback_parts.append("Job Title 'Training Coordinator' created (10/10)")
    else:
        feedback_parts.append("Job Title 'Training Coordinator' missing or inactive (0/10)")

    # 2. Verify Employees
    users = db_state.get('users', [])
    employees = db_state.get('employees', [])
    summaries = db_state.get('summary', [])
    managers = db_state.get('managers', [])

    for expected in expected_employees:
        empid = expected['empid']
        fname = expected['firstname']
        lname = expected['lastname']

        # Find user record (by EMP ID or Name)
        user_record = next((u for u in users if u.get('employeeId') == empid), None)
        if not user_record:
            user_record = next((u for u in users if safe_lower(u.get('firstname')) == safe_lower(fname) 
                                and safe_lower(u.get('lastname')) == safe_lower(lname)), None)

        if not user_record:
            feedback_parts.append(f"{empid} ({fname} {lname}) not found (0/30)")
            continue

        # Employee found
        score += breakdown.get('exists', 4)
        emp_fb = [f"{fname} exists (4/4)"]
        uid = user_record.get('id')

        # Find associated details
        emp_detail = next((e for e in employees if e.get('user_id') == uid), {})
        summ_detail = next((s for s in summaries if s.get('user_id') == uid), {})
        mgr_records = [m for m in managers if m.get('user_id') == uid]

        # A. Check EMP ID
        if safe_lower(user_record.get('employeeId')) == safe_lower(empid):
            score += breakdown.get('empid', 2)
        else:
            emp_fb.append(f"Wrong EMP ID: {user_record.get('employeeId')}")

        # B. Check Department
        actual_dept = dept_lookup.get(user_record.get('department_id'), "")
        if safe_lower(actual_dept) == safe_lower(expected['dept']):
            score += breakdown.get('dept', 5)
        else:
            emp_fb.append(f"Wrong Dept: {actual_dept}")

        # C. Check Job Title
        actual_title = title_lookup.get(user_record.get('jobtitle_id'), "")
        if safe_lower(actual_title) == safe_lower(expected['title']):
            score += breakdown.get('title', 5)
        else:
            emp_fb.append(f"Wrong Title: {actual_title}")

        # D. Check Email
        if safe_lower(user_record.get('emailaddress')) == safe_lower(expected['email']):
            score += breakdown.get('email', 3)
        else:
            emp_fb.append("Wrong/Missing Email")

        # E. Check DOB (look in all possible places Sentrifugo might store it)
        actual_dob = str(emp_detail.get('date_of_birth') or summ_detail.get('date_of_birth') or user_record.get('date_of_birth') or "")
        if actual_dob.startswith(expected['dob']):
            score += breakdown.get('dob', 3)
        else:
            emp_fb.append("Wrong/Missing DOB")

        # F. Check Gender
        actual_gender = str(emp_detail.get('gender') or summ_detail.get('gender') or user_record.get('gender') or "")
        if safe_lower(expected['gender']) in safe_lower(actual_gender):
            score += breakdown.get('gender', 2)
        else:
            emp_fb.append("Wrong/Missing Gender")

        # G. Check Date of Joining
        actual_doj = str(user_record.get('date_of_joining') or summ_detail.get('date_of_joining') or emp_detail.get('date_of_joining') or "")
        if actual_doj.startswith(expected['doj']):
            score += breakdown.get('doj', 3)
        else:
            emp_fb.append("Wrong/Missing Date of Joining")

        # H. Check Manager
        expected_mgr_empid = expected['manager_empid']
        manager_ok = False
        # Look in manager table
        for mr in mgr_records:
            mgr_uid = mr.get('manager_id')
            if mgr_lookup.get(mgr_uid) == expected_mgr_empid:
                manager_ok = True
                break
        
        # Fallback to text matching in summary (Sentrifugo sometimes uses names directly)
        if not manager_ok:
            summ_mgr_name = safe_lower(summ_detail.get('manager_name', ''))
            # Get expected manager name from lookup
            expected_mgr_name = next((safe_lower(m['firstname']) for m in db_state.get('manager_lookup', []) if m['employeeId'] == expected_mgr_empid), "")
            if expected_mgr_name and expected_mgr_name in summ_mgr_name:
                manager_ok = True

        if manager_ok:
            score += breakdown.get('manager', 3)
        else:
            emp_fb.append("Wrong/Missing Manager")

        if len(emp_fb) == 1:
            feedback_parts.append(f"{empid} ({fname}): Fully correct (30/30)")
        else:
            feedback_parts.append(f"{empid} ({fname}): Partial. Issues - {', '.join(emp_fb[1:])}")

    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }