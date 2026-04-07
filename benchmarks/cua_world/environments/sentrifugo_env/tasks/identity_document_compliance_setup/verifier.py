#!/usr/bin/env python3
"""
Verifier for identity_document_compliance_setup task.

Verification Strategy:
1. Parse exported JSON containing full table dumps of Users, Document Types, and Employee Documents.
2. Verify "Passport" and "Work Visa" exist globally. (10 pts each)
3. For each required employee (EMP016, EMP017, EMP018), find their system `user_id`.
4. Scan the employee documents tables to find rows matching the `user_id`.
5. Check if the exact alphanumeric values (Document Number, Issue Date, Expiry Date) are present
   in the matched rows. This approach is completely robust against DB schema or column name variations.
   
Anti-Gaming: Requires the exact alphanumeric strings from the prompt to be physically present in 
the database linked to the correct employee records.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_identity_document_compliance_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_employees = metadata.get('employees', {})
    pass_threshold = metadata.get('pass_threshold', 70)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    users = result.get('users', [])
    doc_types = result.get('doc_types', [])
    emp_docs = result.get('emp_docs', [])
    task_start = result.get('task_start', 0)
    task_end = result.get('task_end', 0)

    score = 0
    feedback_parts = []

    # Anti-gaming: Ensure task actually took time
    if task_start > 0 and task_end > 0 and (task_end - task_start) < 2:
        return {"passed": False, "score": 0, "feedback": "Task completed instantly, likely no operations performed."}

    # 1. Global Document Configuration (20 points)
    passport_exists = False
    visa_exists = False

    for dt in doc_types:
        values = " ".join(str(v).lower() for v in dt.values())
        if "passport" in values:
            passport_exists = True
        if "work visa" in values:
            visa_exists = True

    if passport_exists:
        score += 10
        feedback_parts.append("Global config: Passport exists (10/10)")
    else:
        feedback_parts.append("Global config: Passport missing (0/10)")

    if visa_exists:
        score += 10
        feedback_parts.append("Global config: Work Visa exists (10/10)")
    else:
        feedback_parts.append("Global config: Work Visa missing (0/10)")

    # 2. Employee Specific Documents (80 points total)
    # Map employeeId to internal user id
    emp_id_map = {}
    for u in users:
        eid = str(u.get('employeeId', ''))
        uid = str(u.get('id', ''))
        if eid in expected_employees:
            emp_id_map[eid] = uid

    def check_doc(user_id, num, iss, exp):
        if not user_id:
            return False
        for doc in emp_docs:
            # Check if this row belongs to the user
            row_uid = str(doc.get('user_id', doc.get('employee_id', '')))
            
            # Fallback if specific column name isn't clear: check if user_id is any value
            row_values = [str(v) for v in doc.values()]
            
            if row_uid == str(user_id) or str(user_id) in row_values:
                # Merge all values into a searchable string to bypass schema variations
                all_vals = " ".join(row_values).lower()
                if num.lower() in all_vals and iss.lower() in all_vals and exp.lower() in all_vals:
                    return True
        return False

    # EMP016: 13 pts Passport, 13 pts Visa (26 total)
    # EMP017: 13 pts Passport, 14 pts Visa (27 total)
    # EMP018: 13 pts Passport, 14 pts Visa (27 total)
    employee_scoring = {
        "EMP016": {"passport": 13, "visa": 13},
        "EMP017": {"passport": 13, "visa": 14},
        "EMP018": {"passport": 13, "visa": 14}
    }

    for eid, docs in expected_employees.items():
        uid = emp_id_map.get(eid)
        if not uid:
            feedback_parts.append(f"{eid} not found in system")
            continue

        # Check Passport
        p_data = docs["passport"]
        if check_doc(uid, p_data["num"], p_data["iss"], p_data["exp"]):
            pts = employee_scoring[eid]["passport"]
            score += pts
            feedback_parts.append(f"{eid} Passport correct ({pts}/{pts})")
        else:
            feedback_parts.append(f"{eid} Passport missing/incorrect (0/{employee_scoring[eid]['passport']})")

        # Check Work Visa
        v_data = docs["visa"]
        if check_doc(uid, v_data["num"], v_data["iss"], v_data["exp"]):
            pts = employee_scoring[eid]["visa"]
            score += pts
            feedback_parts.append(f"{eid} Work Visa correct ({pts}/{pts})")
        else:
            feedback_parts.append(f"{eid} Work Visa missing/incorrect (0/{employee_scoring[eid]['visa']})")

    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }