#!/usr/bin/env python3
"""
Verifier for create_user_profile task.

Checks:
1. "Guidance Counselor" profile exists and was created during the task.
2. Students module has Full Access (can_use=Y, can_edit=Y).
3. Scheduling module has Read-Only Access (can_use=Y, can_edit=N).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_user_profile(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    passed = False
    
    # 1. Check if profile exists
    if not result.get("profile_found"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Profile 'Guidance Counselor' not found in database (or was not created as a new ID)."
        }
    
    score += 30
    feedback.append("Profile 'Guidance Counselor' created successfully.")
    
    permissions = result.get("permissions", [])
    
    # Helper to check permissions for a module keyword
    def check_module_perms(keyword):
        # OpenSIS permissions are often granular (e.g., 'students/Student.php', 'students/Search.php')
        # We look for the main module entry or consistent settings across entries
        relevant_perms = [p for p in permissions if keyword in p['modname'].lower()]
        if not relevant_perms:
            return None
        
        # Check if ANY main entry allows use
        can_use = any(p['can_use'] == 'Y' for p in relevant_perms)
        
        # Check if ANY main entry allows edit
        # Note: If multiple entries exist, strict read-only means NO entry should have can_edit='Y'
        can_edit = any(p['can_edit'] == 'Y' for p in relevant_perms)
        
        return {"can_use": can_use, "can_edit": can_edit}

    # 2. Check Students Module (Full Access Required)
    students_perm = check_module_perms("students")
    if students_perm:
        if students_perm["can_use"]:
            score += 15
            feedback.append("Students module access enabled.")
            if students_perm["can_edit"]:
                score += 20
                feedback.append("Students module edit permission enabled (Correct).")
            else:
                feedback.append("Students module edit permission MISSING (Expected Full Access).")
        else:
            feedback.append("Students module access NOT enabled.")
    else:
        feedback.append("No permissions found for Students module (Default is often No Access).")

    # 3. Check Scheduling Module (Read-Only Required)
    # This is the tricky part: Must have Access (Use=Y) but NO Edit (Edit=N)
    sched_perm = check_module_perms("scheduling")
    if sched_perm:
        if sched_perm["can_use"]:
            score += 15
            feedback.append("Scheduling module access enabled.")
            if not sched_perm["can_edit"]:
                score += 20
                feedback.append("Scheduling module edit permission disabled (Correct: Read-Only).")
            else:
                feedback.append("Scheduling module has EDIT permission (Failed: Should be Read-Only).")
        else:
            feedback.append("Scheduling module access NOT enabled.")
    else:
        feedback.append("No permissions found for Scheduling module.")

    # 4. Check for leakage (optional - bonus points or just validation)
    # Ensure they didn't enable Grades by accident
    grades_perm = check_module_perms("grades")
    if grades_perm and grades_perm["can_use"]:
        feedback.append("Warning: Grades module access enabled (Task specified no other access).")
    
    # Determine Pass/Fail
    # Passing requires Profile exists + Students RW + Scheduling RO
    # Max Score = 30 + 15 + 20 + 15 + 20 = 100
    if score >= 85:
        passed = True
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }