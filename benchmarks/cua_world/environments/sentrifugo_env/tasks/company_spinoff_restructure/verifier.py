#!/usr/bin/env python3
"""
Verifier for company_spinoff_restructure@1.
Validates organizational state via programmatic checks extracted from the container DB.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_company_spinoff_restructure(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available."}

    metadata = task_info.get('metadata', {})
    pass_threshold = metadata.get('pass_threshold', 70)

    # 1. Safely retrieve the task result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    employees = result.get('employees', {})
    departments = result.get('departments', {})

    # ====================================================================
    # Criterion 1: New Department Created & Active (15 pts)
    # ====================================================================
    vendor_mgmt = departments.get('Vendor Management')
    if vendor_mgmt and vendor_mgmt.get('isactive') == 1:
        score += 15
        feedback.append("[Pass] 'Vendor Management' department created and active. (+15)")
    else:
        feedback.append("[Fail] 'Vendor Management' department missing or inactive.")

    # ====================================================================
    # Criterion 2: Retained Employees Moved and Safe (30 pts max)
    # ====================================================================
    # EMP011
    emp11 = employees.get('EMP011', {})
    if emp11.get('isactive') == 1 and emp11.get('dept') == 'Vendor Management':
        score += 15
        feedback.append("[Pass] EMP011 successfully retained in Vendor Management. (+15)")
    else:
        feedback.append(f"[Fail] EMP011 state incorrect (Active: {emp11.get('isactive')}, Dept: {emp11.get('dept')}).")

    # EMP019
    emp19 = employees.get('EMP019', {})
    if emp19.get('isactive') == 1 and emp19.get('dept') == 'Vendor Management':
        score += 15
        feedback.append("[Pass] EMP019 successfully retained in Vendor Management. (+15)")
    else:
        feedback.append(f"[Fail] EMP019 state incorrect (Active: {emp19.get('isactive')}, Dept: {emp19.get('dept')}).")

    # ====================================================================
    # Criterion 3: Old Departments Deactivated (20 pts max)
    # ====================================================================
    mkt_dept = departments.get('Marketing', {})
    if mkt_dept.get('isactive') == 0:
        score += 10
        feedback.append("[Pass] Marketing department successfully deactivated. (+10)")
    else:
        feedback.append("[Fail] Marketing department still active.")

    sales_dept = departments.get('Sales', {})
    if sales_dept.get('isactive') == 0:
        score += 10
        feedback.append("[Pass] Sales department successfully deactivated. (+10)")
    else:
        feedback.append("[Fail] Sales department still active.")

    # ====================================================================
    # Criterion 4: Spinoff Employees Deactivated (20 pts max)
    # ====================================================================
    spinoffs = ['EMP005', 'EMP008', 'EMP014', 'EMP018']
    deactivated_count = sum(1 for e in spinoffs if employees.get(e, {}).get('isactive') == 0)
    
    if deactivated_count == 4:
        score += 20
        feedback.append("[Pass] All 4 required spinoff employees successfully deactivated. (+20)")
    else:
        pts = deactivated_count * 5
        score += pts
        feedback.append(f"[Partial] {deactivated_count}/4 spinoff employees deactivated. (+{pts})")

    # ====================================================================
    # Criterion 5: Control Employee Safe (Anti-Gaming) (15 pts)
    # ====================================================================
    # Ensures the agent didn't just select all rows in the DB and click "Deactivate"
    emp03 = employees.get('EMP003', {})
    if emp03.get('isactive') == 1:
        score += 15
        feedback.append("[Pass] Control employee (EMP003) remained untouched. (+15)")
    else:
        feedback.append("[Fail] ANTI-GAMING TRIGGERED: Control employee in Finance was deactivated.")

    # ====================================================================
    # Final Result Compilation
    # ====================================================================
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "vendor_mgmt_active": bool(vendor_mgmt and vendor_mgmt.get('isactive') == 1),
            "retained_emp11_safe": bool(emp11.get('isactive') == 1),
            "spinoff_deactivated_count": deactivated_count
        }
    }