#!/usr/bin/env python3
"""Verifier for Configure Course Requests task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_course_requests(traj, env_info, task_info):
    """
    Verify that the course request feature is configured correctly and used.

    Scoring (100 points):
    - Config: Course requests enabled (20 points)
    - Config: Default category is 'Science' (20 points)
    - Usage: Request exists with correct name (30 points)
    - Usage: Request submitted by teacher1 (15 points)
    - Usage: Request linked to 'Science' category (15 points)

    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/course_request_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # Load Reference Data
        ref_science_id = int(result.get('ref_science_id', 0))
        ref_teacher_id = int(result.get('ref_teacher_id', 0))

        # Criterion 1: Feature Enabled (20 pts)
        # 1 = Enabled
        current_enabled = int(result.get('current_enabled', 0))
        if current_enabled == 1:
            score += 20
            subscores["feature_enabled"] = True
            feedback_parts.append("Course requests enabled")
        else:
            subscores["feature_enabled"] = False
            feedback_parts.append("Course requests NOT enabled")

        # Criterion 2: Default Category (20 pts)
        current_default_cat = int(result.get('current_default_cat', 0))
        if current_default_cat == ref_science_id and ref_science_id > 0:
            score += 20
            subscores["default_cat_correct"] = True
            feedback_parts.append("Default category set to Science")
        else:
            subscores["default_cat_correct"] = False
            feedback_parts.append(f"Default category incorrect (ID: {current_default_cat}, Expected: {ref_science_id})")

        # Criterion 3: Request Exists (30 pts)
        request_found = result.get('request_found', False)
        request_data = result.get('request', {})
        
        if request_found:
            score += 30
            subscores["request_created"] = True
            feedback_parts.append("Course request 'Advanced Quantum Mechanics' found")
        else:
            subscores["request_created"] = False
            feedback_parts.append("Course request NOT found")

        # Criterion 4: Requester Identity (15 pts) - Anti-gaming
        # Must be teacher1, not admin
        requester_id = int(request_data.get('requester_id', 0) or 0)
        if request_found and requester_id == ref_teacher_id and ref_teacher_id > 0:
            score += 15
            subscores["requester_correct"] = True
            feedback_parts.append("Request submitted by teacher1")
        elif request_found:
            subscores["requester_correct"] = False
            feedback_parts.append(f"Request submitted by wrong user (ID: {requester_id}, Expected: {ref_teacher_id})")

        # Criterion 5: Request Category (15 pts)
        # Should match Science category (either via default setting or manual selection)
        req_cat_id = int(request_data.get('category_id', 0) or 0)
        if request_found and req_cat_id == ref_science_id and ref_science_id > 0:
            score += 15
            subscores["req_cat_correct"] = True
            feedback_parts.append("Request linked to Science category")
        elif request_found:
            subscores["req_cat_correct"] = False
            feedback_parts.append(f"Request linked to wrong category (ID: {req_cat_id}, Expected: {ref_science_id})")

        # Final check
        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON in result: {str(e)}"}
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}