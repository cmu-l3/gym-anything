#!/usr/bin/env python3
"""Verifier for Configure Blind Marking Assignment task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_blind_marking_assignment(traj, env_info, task_info):
    """
    Verify that the course 'Business Ethics' (ETHICS101) was created and
    contains an assignment with Blind Marking, Workflow, and Allocation enabled.

    Scoring (100 points):
    - Course 'ETHICS101' created in correct category (20 points)
    - Assignment 'Final Capstone Paper' exists (20 points)
    - Blind Marking Enabled (20 points)
    - Marking Workflow Enabled (15 points)
    - Marking Allocation Enabled (15 points)
    - PDF Restriction Configured (10 points)

    Pass threshold: 75 points (Must include Course, Assignment, and Blind Marking)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/configure_blind_marking_assignment_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # 1. Verify Course Creation (20 pts)
        course_found = result.get('course_found', False)
        category_name = result.get('category_name', '').lower()
        created_fresh = result.get('course_created_during_task', False)

        if course_found:
            if 'humanities' in category_name:
                score += 20
                subscores["course_created"] = True
                feedback_parts.append("Course 'ETHICS101' created in Humanities")
            else:
                score += 10
                subscores["course_created"] = False
                feedback_parts.append(f"Course created but wrong category ('{result.get('category_name')}')")
        else:
            feedback_parts.append("Course 'ETHICS101' NOT found")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": {"course_created": False}
            }

        # 2. Verify Assignment Exists (20 pts)
        assign_found = result.get('assign_found', False)
        if assign_found:
            score += 20
            subscores["assign_created"] = True
            feedback_parts.append("Assignment found")
        else:
            feedback_parts.append("Assignment 'Final Capstone Paper' NOT found")
            # Can't verify settings if assignment doesn't exist
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # 3. Verify Blind Marking (20 pts)
        blind_marking = int(result.get('blind_marking', 0))
        if blind_marking == 1:
            score += 20
            subscores["blind_marking"] = True
            feedback_parts.append("Blind marking enabled")
        else:
            subscores["blind_marking"] = False
            feedback_parts.append("Blind marking NOT enabled")

        # 4. Verify Marking Workflow (15 pts)
        marking_workflow = int(result.get('marking_workflow', 0))
        if marking_workflow == 1:
            score += 15
            subscores["marking_workflow"] = True
            feedback_parts.append("Marking workflow enabled")
        else:
            subscores["marking_workflow"] = False
            feedback_parts.append("Marking workflow NOT enabled")

        # 5. Verify Marking Allocation (15 pts)
        marking_allocation = int(result.get('marking_allocation', 0))
        if marking_allocation == 1:
            score += 15
            subscores["marking_allocation"] = True
            feedback_parts.append("Marking allocation enabled")
        else:
            subscores["marking_allocation"] = False
            feedback_parts.append("Marking allocation NOT enabled")

        # 6. Verify PDF Restriction (10 pts)
        file_types = result.get('file_types', '').lower()
        if '.pdf' in file_types:
            score += 10
            subscores["file_restriction"] = True
            feedback_parts.append("PDF restriction correct")
        elif 'pdf' in file_types: # Accept 'pdf' without dot
            score += 10
            subscores["file_restriction"] = True
            feedback_parts.append("PDF restriction correct")
        else:
            subscores["file_restriction"] = False
            feedback_parts.append(f"File types mismatch: '{file_types}'")

        # Anti-gaming check: Ensure modified during task
        if not result.get('assign_modified_during_task', False):
            feedback_parts.append("WARNING: Assignment not modified during task duration")
            # We don't fail immediately, but this flag is available for auditing

        passed = score >= 75 and subscores.get("blind_marking", False)

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - export may have failed"}
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "Invalid JSON in result file"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}