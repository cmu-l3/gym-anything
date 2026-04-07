#!/usr/bin/env python3
"""Verifier for Create Custom Role Assignment task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_custom_role_assignment(traj, env_info, task_info):
    """
    Verify creation of custom 'Course Auditor' role and its assignment.
    
    Scoring Criteria:
    1. Role exists with shortname 'courseauditor' (15 pts)
    2. Role name matches 'Course Auditor' (10 pts)
    3. Role is newly created (ID > initial max) (Anti-gaming check)
    4. Role context includes Course (contextlevel 50) (15 pts)
    5. Capabilities set correctly (30 pts total, 10 each):
       - moodle/course:view
       - moodle/grade:viewall
       - moodle/course:viewparticipants
    6. Role assigned to 'teacher2' in 'ENG201' (30 pts)
    
    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_shortname = metadata.get('role_shortname', 'courseauditor')
    expected_name = metadata.get('role_name', 'Course Auditor')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_custom_role_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}
        
        role_found = result.get('role_found', False)
        role = result.get('role', {})
        assignment = result.get('assignment', {})
        initial_max_id = int(result.get('initial_max_role_id', 0))
        current_role_id = int(role.get('id', 0))

        # 1. Role Existence & Identity (25 pts)
        if role_found:
            # Check if newly created
            if current_role_id > initial_max_id:
                score += 15
                subscores["role_created"] = True
                feedback_parts.append("Role 'courseauditor' created")
            else:
                score += 5 # Reduced points if it pre-existed (unlikely with setup script, but possible if reused)
                feedback_parts.append("Role found (but id not > initial)")

            # Check Name
            actual_name = role.get('name', '')
            if expected_name.lower() in actual_name.lower():
                score += 10
                subscores["name_match"] = True
                feedback_parts.append("Role name correct")
            else:
                feedback_parts.append(f"Role name mismatch ('{actual_name}')")
        else:
            feedback_parts.append("Role 'courseauditor' NOT found")
            return {"passed": False, "score": 0, "feedback": "Role not created"}

        # 2. Context Level (15 pts)
        if role.get('context_course_enabled', False):
            score += 15
            subscores["context_correct"] = True
            feedback_parts.append("Role enabled for Course context")
        else:
            feedback_parts.append("Role NOT enabled for Course context")

        # 3. Capabilities (30 pts)
        caps = role.get('capabilities', {})
        # permission 1 = Allow
        cap_score = 0
        
        if int(caps.get('moodle_course_view', 0)) == 1:
            cap_score += 10
            feedback_parts.append("View course: OK")
        else:
            feedback_parts.append("View course: FAIL")
            
        if int(caps.get('moodle_grade_viewall', 0)) == 1:
            cap_score += 10
            feedback_parts.append("View grades: OK")
        else:
            feedback_parts.append("View grades: FAIL")
            
        if int(caps.get('moodle_course_viewparticipants', 0)) == 1:
            cap_score += 10
            feedback_parts.append("View participants: OK")
        else:
            feedback_parts.append("View participants: FAIL")
            
        score += cap_score
        subscores["capabilities_score"] = cap_score

        # 4. Assignment (30 pts)
        if assignment.get('found', False):
            score += 30
            subscores["assignment_correct"] = True
            feedback_parts.append("Role assigned to user in course")
        else:
            feedback_parts.append("Role NOT assigned to target user in target course")

        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except Exception as e:
        logger.error(f"Verification failed: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}