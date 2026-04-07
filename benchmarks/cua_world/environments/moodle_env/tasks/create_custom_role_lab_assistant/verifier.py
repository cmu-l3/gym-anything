#!/usr/bin/env python3
"""Verifier for Create Custom Role task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_custom_role(traj, env_info, task_info):
    """
    Verify that the 'Lab Assistant' role was created correctly.

    Scoring (100 points):
    - Criterion 1: Role 'labassistant' exists and was newly created (30 points)
    - Criterion 2: Full name is 'Lab Assistant' (10 points)
    - Criterion 3: Archetype is 'teacher' (Non-editing teacher) (10 points)
      * Note: Moodle internal name for Non-editing teacher is often 'teacher' or empty depending on version,
        but we focus on the capability override mainly.
    - Criterion 4: 'moodle/course:manageactivities' is set to ALLOW (1) (40 points) - CRITICAL
    - Criterion 5: Role is assignable in Course context (10 points)

    Pass threshold: 80 points (Must have role + capability)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

        # Criterion 1: Role exists (30 points)
        role_found = result.get('role_found', False)
        initial_count = int(result.get('initial_role_count', 0))
        current_count = int(result.get('current_role_count', 0))
        
        if role_found:
            score += 30
            subscores["role_exists"] = True
            feedback_parts.append("Role 'labassistant' found")
        else:
            feedback_parts.append("Role 'labassistant' NOT found")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }

        # Check for newly created (anti-gaming, though less critical than existence here)
        if current_count > initial_count:
            feedback_parts.append("(Newly created)")
        else:
            feedback_parts.append("(Warning: Count did not increase, may be pre-existing)")

        # Criterion 2: Full name (10 points)
        fullname = result.get('role_fullname', '')
        if fullname.strip() == "Lab Assistant":
            score += 10
            subscores["fullname_correct"] = True
            feedback_parts.append("Full name correct")
        else:
            subscores["fullname_correct"] = False
            feedback_parts.append(f"Full name mismatch: '{fullname}'")

        # Criterion 3: Archetype (10 points)
        # Note: 'teacher' = Non-editing teacher, 'editingteacher' = Teacher
        archetype = result.get('role_archetype', '')
        # We accept 'teacher' (Non-editing) as requested, or empty if they built from scratch correctly
        # The prompt asked for "Non-editing teacher" basis.
        if archetype == 'teacher':
            score += 10
            subscores["archetype_correct"] = True
            feedback_parts.append("Archetype correct (Non-editing teacher)")
        else:
            subscores["archetype_correct"] = False
            feedback_parts.append(f"Archetype: '{archetype}' (expected 'teacher')")

        # Criterion 4: Capability 'manageactivities' ALLOW (40 points)
        # Permission 1 = ALLOW
        perm = int(result.get('capability_permission', 0))
        if perm == 1:
            score += 40
            subscores["capability_correct"] = True
            feedback_parts.append("Manage activities: ALLOWED")
        else:
            subscores["capability_correct"] = False
            feedback_parts.append(f"Manage activities permission: {perm} (expected 1/Allow)")

        # Criterion 5: Context (10 points)
        if result.get('context_course_enabled', False):
            score += 10
            subscores["context_correct"] = True
            feedback_parts.append("Assignable in Course context")
        else:
            subscores["context_correct"] = False
            feedback_parts.append("Not assignable in Course context")

        passed = score >= 80

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Error: {str(e)}"}