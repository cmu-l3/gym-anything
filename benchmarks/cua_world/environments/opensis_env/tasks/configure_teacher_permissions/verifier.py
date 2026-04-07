#!/usr/bin/env python3
"""
Verifier for configure_teacher_permissions task.

Verification Criteria:
1. Teacher profile (ID=2) must exist (5 pts)
2. Permissions count must have increased from initial 0 (Anti-gaming)
3. Students module: can_use='Y' (15 pts), can_edit='Y' (10 pts)
4. Attendance module: can_use='Y' (15 pts), can_edit='Y' (10 pts)
5. Grades module: can_use='Y' (15 pts), can_edit='Y' (10 pts)
6. NO access to forbidden modules (School Setup, User Mgmt) (20 pts)

Pass Threshold: 70 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_teacher_permissions(traj, env_info, task_info):
    """
    Verify that teacher permissions were correctly configured in the database.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ================================================================
    # 1. Load Result JSON
    # ================================================================
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

    score = 0
    feedback_parts = []
    
    # Metadata targets
    metadata = task_info.get('metadata', {})
    req_mods = metadata.get('required_modules', {
        "students": "students/Student.php",
        "attendance": "attendance/TakeAttendance.php",
        "grades": "grades/Grades.php"
    })
    forbidden_mods = metadata.get('forbidden_modules', ["schoolsetup/Schools.php", "users/User.php"])

    # Extract permission map for easier checking
    # Map modname -> {can_use, can_edit}
    agent_perms = {p['modname']: p for p in result.get('permissions', [])}
    
    # ================================================================
    # 2. Basic Integrity Checks (5 pts)
    # ================================================================
    if result.get('teacher_profile_exists', False):
        score += 5
        feedback_parts.append("Teacher profile exists")
    else:
        feedback_parts.append("Teacher profile MISSING")
        return {"passed": False, "score": 0, "feedback": "Teacher profile deleted or missing"}

    # Anti-gaming: Ensure permissions were actually added
    current_count = len(agent_perms)
    initial_count = result.get('initial_count', 0)
    
    if current_count <= initial_count and initial_count == 0:
        return {"passed": False, "score": 5, "feedback": "No permissions were added (count is 0)"}

    # ================================================================
    # 3. Verify Required Modules (75 pts total)
    # ================================================================
    
    # Students Module (25 pts)
    mod_students = req_mods["students"]
    perm_students = agent_perms.get(mod_students)
    
    if perm_students:
        if perm_students.get('can_use') == 'Y':
            score += 15
            feedback_parts.append("Students access: YES")
        else:
            feedback_parts.append("Students access: NO")
            
        if perm_students.get('can_edit') == 'Y':
            score += 10
            feedback_parts.append("Students edit: YES")
        else:
            feedback_parts.append("Students edit: NO")
    else:
        feedback_parts.append("Students module NOT configured")

    # Attendance Module (25 pts)
    mod_attendance = req_mods["attendance"]
    perm_attendance = agent_perms.get(mod_attendance)
    
    if perm_attendance:
        if perm_attendance.get('can_use') == 'Y':
            score += 15
            feedback_parts.append("Attendance access: YES")
        else:
            feedback_parts.append("Attendance access: NO")
            
        if perm_attendance.get('can_edit') == 'Y':
            score += 10
            feedback_parts.append("Attendance edit: YES")
        else:
            feedback_parts.append("Attendance edit: NO")
    else:
        feedback_parts.append("Attendance module NOT configured")

    # Grades Module (25 pts)
    mod_grades = req_mods["grades"]
    perm_grades = agent_perms.get(mod_grades)
    
    if perm_grades:
        if perm_grades.get('can_use') == 'Y':
            score += 15
            feedback_parts.append("Grades access: YES")
        else:
            feedback_parts.append("Grades access: NO")
            
        if perm_grades.get('can_edit') == 'Y':
            score += 10
            feedback_parts.append("Grades edit: YES")
        else:
            feedback_parts.append("Grades edit: NO")
    else:
        feedback_parts.append("Grades module NOT configured")

    # ================================================================
    # 4. Verify Forbidden Modules (20 pts)
    # ================================================================
    over_permissioned = False
    for forbidden in forbidden_mods:
        perm = agent_perms.get(forbidden)
        if perm and perm.get('can_use') == 'Y':
            over_permissioned = True
            feedback_parts.append(f"FAIL: Granted forbidden access to {forbidden}")
    
    if not over_permissioned:
        score += 20
        feedback_parts.append("Correctly restricted admin modules")
    else:
        feedback_parts.append("Security Violation: Too many permissions granted")

    # ================================================================
    # 5. Final Result
    # ================================================================
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "permissions_found": list(agent_perms.keys()),
            "score_breakdown": score
        }
    }