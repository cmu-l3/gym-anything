#!/usr/bin/env python3
"""
Verifier for Oracle RBAC Security Implementation task.

Scoring Breakdown (100 points total):
1. Roles Created (15 pts): 5 pts each for HR_READONLY, HR_ANALYST, HR_MANAGER.
2. Users Created & Assigned (21 pts): 7 pts each for correct role assignment.
3. View Implementation (25 pts):
   - V_EMPLOYEE_PUBLIC exists (5)
   - V_EMPLOYEE_PUBLIC masks sensitive columns (10)
   - V_DEPT_SUMMARY exists (5)
   - V_DEPT_SUMMARY is aggregated (row count < 100) (5)
4. Privilege Correctness (Live Tests & Grants) (29 pts):
   - Reader can query view (5)
   - Reader CANNOT query table (5)
   - Manager can DML (8)
   - Specific privileges found in dictionary (11)
5. Report File (10 pts): Exists, size > 500b, contains keywords.

Pass Threshold: 60 points
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rbac_security(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/rbac_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Roles (15 pts)
    roles = result.get("roles_exist", [])
    for role in ["HR_READONLY", "HR_ANALYST", "HR_MANAGER"]:
        if role in roles:
            score += 5
            feedback_parts.append(f"Role {role} exists (+5)")
    
    # 2. Users & Assignments (21 pts)
    assignments = result.get("role_assignments", {})
    users_checked = [
        ("APP_READER", "HR_READONLY"),
        ("APP_ANALYST", "HR_ANALYST"),
        ("APP_MANAGER", "HR_MANAGER")
    ]
    for user, role in users_checked:
        if user in assignments:
            # Check for direct or indirect assignment? The task implies direct.
            # But checking if the role is present in the list is sufficient.
            if role in assignments[user]:
                score += 7
                feedback_parts.append(f"User {user} has role {role} (+7)")
            else:
                feedback_parts.append(f"User {user} exists but missing role {role}")
        else:
            feedback_parts.append(f"User {user} not found or has no roles")

    # 3. View Implementation (25 pts)
    view_defs = result.get("view_definitions", {})
    
    # V_EMPLOYEE_PUBLIC
    vep = view_defs.get("V_EMPLOYEE_PUBLIC", {})
    if vep.get("exists"):
        score += 5
        feedback_parts.append("V_EMPLOYEE_PUBLIC exists (+5)")
        cols = vep.get("columns", [])
        forbidden = ["SALARY", "COMMISSION_PCT", "MANAGER_ID"]
        found_forbidden = [c for c in cols if c in forbidden]
        
        if not found_forbidden:
            score += 10
            feedback_parts.append("V_EMPLOYEE_PUBLIC correctly masks sensitive columns (+10)")
        else:
            feedback_parts.append(f"V_EMPLOYEE_PUBLIC exposes forbidden columns: {found_forbidden}")
    else:
        feedback_parts.append("V_EMPLOYEE_PUBLIC missing")

    # V_DEPT_SUMMARY
    vds = view_defs.get("V_DEPT_SUMMARY", {})
    if vds.get("exists"):
        score += 5
        feedback_parts.append("V_DEPT_SUMMARY exists (+5)")
        
        # Check if aggregated (row count should be small, around ~27 departments, definitely not 107 employees)
        row_count = vds.get("row_count", 999)
        if 0 < row_count < 50:
            score += 5
            feedback_parts.append(f"V_DEPT_SUMMARY appears aggregated ({row_count} rows) (+5)")
        else:
            feedback_parts.append(f"V_DEPT_SUMMARY row count suspect ({row_count} rows) - expected aggregation")
    else:
        feedback_parts.append("V_DEPT_SUMMARY missing")

    # 4. Privileges & Live Tests (29 pts)
    live_tests = result.get("live_access_tests", {})
    
    if live_tests.get("reader_view_access", {}).get("passed"):
        score += 5
        feedback_parts.append("Live Test: Reader can query view (+5)")
    else:
        feedback_parts.append("Live Test: Reader CANNOT query view")

    if live_tests.get("reader_table_denial", {}).get("passed"):
        score += 5
        feedback_parts.append("Live Test: Reader denied on table (+5)")
    else:
        feedback_parts.append("Live Test: Reader WAS ABLE to query table (Security Fail)")

    if live_tests.get("manager_dml", {}).get("passed"):
        score += 8
        feedback_parts.append("Live Test: Manager can perform DML (+8)")
    else:
        feedback_parts.append("Live Test: Manager DML failed")

    # Check specific grants in dictionary (backup/completeness)
    grants = result.get("privilege_grants", {})
    # Check if HR_MANAGER has INSERT/UPDATE/DELETE (checking dictionary strings)
    manager_privs = str(grants.get("HR_MANAGER", []))
    if "INSERT" in manager_privs and "UPDATE" in manager_privs and "DELETE" in manager_privs:
        score += 11
        feedback_parts.append("HR_MANAGER has full DML privileges (+11)")
    else:
        feedback_parts.append("HR_MANAGER missing some DML privileges in metadata")

    # 5. Report File (10 pts)
    report = result.get("report_file", {})
    if report.get("exists"):
        if report.get("size", 0) >= 500:
            score += 5
            feedback_parts.append("Report file valid size (+5)")
        else:
            feedback_parts.append("Report file too small")
            
        content = report.get("content_preview", "").upper()
        if "HR_READONLY" in content and "APP_READER" in content:
            score += 5
            feedback_parts.append("Report content verifies (+5)")
    else:
        feedback_parts.append("Report file missing")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }