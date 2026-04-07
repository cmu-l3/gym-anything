#!/usr/bin/env python3
"""
Verifier for Configure Course Privacy Permissions task.

Verifies:
1. Permissions are overridden in the specific COURSE context (not globally).
2. The target role (Student) is modified.
3. The capability 'moodle/course:viewparticipants' is set to PREVENT (-1) or PROHIBIT (-1000).
4. The global role definition remains unchanged.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_course_privacy_permissions(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    course_override_found = result.get("course_override_found", False)
    course_perm_value = int(result.get("course_permission_value", 0))
    modified_during_task = result.get("modified_during_task", False)
    global_changed = result.get("global_permission_changed", False)
    global_perm_value = int(result.get("global_permission_value", 0))

    # CRITERION 1: Global Safety Check (Critical Fail)
    # If the user changed the global role definition (System Context), they fail.
    # We check if global was changed OR if global is now set to Prevent/Prohibit (if it wasn't before).
    if global_changed:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"CRITICAL FAIL: You modified the global/site-wide role definition. The task required an override ONLY for the specific course."
        }
    
    # If global is Prevent/Prohibit but wasn't changed (unlikely given setup clears it), 
    # it implies bad setup, but if 'global_changed' is False, we trust setup.
    
    # CRITERION 2: Course Override Existence (30 pts)
    if course_override_found:
        score += 30
        feedback_parts.append("Course-level override found")
    else:
        feedback_parts.append("No course-level permission override found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # CRITERION 3: Correct Permission Value (40 pts)
    # -1 = Prevent, -1000 = Prohibit. Both achieve the goal of blocking access.
    if course_perm_value == -1:
        score += 40
        feedback_parts.append("Permission correctly set to PREVENT")
    elif course_perm_value == -1000:
        score += 40
        feedback_parts.append("Permission set to PROHIBIT (acceptable)")
    elif course_perm_value == 1:
        feedback_parts.append("Permission set to ALLOW (incorrect)")
    else:
        feedback_parts.append(f"Permission set to unknown value: {course_perm_value}")

    # CRITERION 4: Modified During Task (30 pts)
    # Ensures the agent actually did the work and didn't rely on pre-existing state
    if modified_during_task:
        score += 30
        feedback_parts.append("Change verified during task session")
    else:
        feedback_parts.append("Change timestamp is old or invalid (anti-gaming check failed)")

    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }