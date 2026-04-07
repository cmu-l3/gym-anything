#!/usr/bin/env python3
"""
Verifier for corporate_divestiture_segregation task.

Scoring (100 pts total):
  - Job Title created & active: 5 pts
  - Employment Status created & active: 5 pts
  - Per target employee (EMP008, EMP010, EMP012, EMP015, EMP018, EMP020):
    - Job Title updated correctly: 5 pts
    - Employment Status updated correctly: 5 pts
    - Email domain updated to @qaserve.com with intact prefix: 5 pts
    Total per employee: 15 pts
  - Control employee modification penalty: -20 pts

Pass threshold: 70 pts
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_corporate_divestiture_segregation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
            
    if not result:
        return {"passed": False, "score": 0, "feedback": "Result JSON is empty or missing"}

    score = 0
    feedback_parts = []
    
    # 1. Check Job Title
    job_titles = result.get('jobtitles', [])
    divest_jt_id = None
    for jt in job_titles:
        if jt.get('jobtitlename', '').strip().lower() == 'divestiture transition staff':
            if str(jt.get('isactive', '1')) == '1':
                divest_jt_id = jt.get('id')
                break
    
    if divest_jt_id:
        score += 5
        feedback_parts.append("Job Title 'Divestiture Transition Staff' created")
    else:
        feedback_parts.append("Job Title 'Divestiture Transition Staff' NOT found/active")

    # 2. Check Employment Status
    # Sentrifugo schema versions vary, so we dynamically scan status tables
    divest_es_id = None
    status_tables_data = result.get('status_tables_data', {})
    for table_name, rows in status_tables_data.items():
        for row in rows:
            for k, v in row.items():
                if v and 'divested entity' in str(v).lower():
                    if str(row.get('isactive', '1')) == '1':
                        divest_es_id = row.get('id')
                        break
            if divest_es_id:
                break
        if divest_es_id:
            break
            
    if divest_es_id:
        score += 5
        feedback_parts.append("Employment Status 'Divested Entity' created")
    else:
        feedback_parts.append("Employment Status 'Divested Entity' NOT found/active")

    # 3. Check Targeted Employees
    users = {u.get('employeeId'): u for u in result.get('users', [])}
    # map user_id back to employeeId for summary records
    user_id_to_empid = {u.get('id'): u.get('employeeId') for u in result.get('users', [])}
    summaries = {}
    for s in result.get('summary', []):
        empid = user_id_to_empid.get(s.get('user_id'))
        if empid:
            summaries[empid] = s
    
    target_emp_ids = ['EMP008', 'EMP010', 'EMP012', 'EMP015', 'EMP018', 'EMP020']
    
    for empid in target_emp_ids:
        user = users.get(empid, {})
        summary = summaries.get(empid, {})
        
        emp_score = 0
        emp_fb = []
        
        # Check Job Title (5 pts)
        actual_jt_id = user.get('jobtitle_id')
        actual_jt_name = summary.get('jobtitle_name', '')
        if (divest_jt_id and actual_jt_id and str(actual_jt_id) == str(divest_jt_id)) or ('divestiture' in actual_jt_name.lower()):
            emp_score += 5
        else:
            emp_fb.append("JT wrong")
            
        # Check Employment Status (5 pts)
        es_ok = False
        if divest_es_id:
            for k, v in user.items():
                if 'status' in k.lower() and str(v) == str(divest_es_id):
                    es_ok = True
                    break
            if not es_ok:
                for k, v in summary.items():
                    if 'status' in k.lower() and str(v) == str(divest_es_id):
                        es_ok = True
                        break
        # Fallback to string match
        if not es_ok:
            for k, v in summary.items():
                if v and 'divested entity' in str(v).lower():
                    es_ok = True
                    break
                    
        if es_ok:
            emp_score += 5
        else:
            emp_fb.append("Status wrong")
            
        # Check Email (5 pts)
        email = user.get('emailaddress', '').strip().lower()
        if email.endswith('@qaserve.com') and not email.startswith('@'):
            prefix = email.split('@')[0]
            # Verify prefix wasn't blown away or corrupted to just a single char
            if len(prefix) >= 3:
                emp_score += 5
            else:
                emp_fb.append("Email prefix corrupted")
        else:
            emp_fb.append(f"Email domain wrong ({email})")
            
        score += emp_score
        
        if emp_score == 15:
            feedback_parts.append(f"{empid} fully updated")
        else:
            feedback_parts.append(f"{empid} partial ({emp_score}/15): {', '.join(emp_fb)}")
            
    # 4. Check control employee EMP005 (Anti-gaming check)
    control_user = users.get('EMP005', {})
    if control_user:
        c_email = control_user.get('emailaddress', '').lower()
        if '@qaserve.com' in c_email:
            feedback_parts.append("WARNING: Control employee EMP005 was incorrectly updated! Deducting 20 pts.")
            score = max(0, score - 20)

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }