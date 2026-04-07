#!/usr/bin/env python3
"""Verifier for Course Meta Link Enrollment task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_course_meta_link_enrollment(traj, env_info, task_info):
    """
    Verify that a Course Meta Link was configured on BIO101-LAB pointing to BIO101.

    Scoring (100 points):
    - Criterion 1: Meta link method exists on child course (40 points)
    - Criterion 2: Meta link points to correct parent course (40 points)
    - Criterion 3: Meta link is enabled (10 points)
    - Criterion 4: Students are actually synced (10 points)

    Pass threshold: 80 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/meta_link_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        parent_id = result.get('parent_course_id', 0)
        child_id = result.get('child_course_id', 0)
        
        # Criterion 1: Meta Link Exists (40 pts)
        meta_exists = result.get('meta_link_exists', False)
        if meta_exists:
            score += 40
            subscores["method_exists"] = True
            feedback_parts.append("Meta link method added")
        else:
            subscores["method_exists"] = False
            feedback_parts.append("Meta link method NOT found")
            return {
                "passed": False,
                "score": 0,
                "feedback": "No meta link configured on the course",
                "subscores": subscores
            }

        # Criterion 2: Correct Linked Course (40 pts)
        # The export script only finds the row if customint1 matches parent_id
        # So if meta_exists is true, this is implicitly true based on the SQL logic
        # But we double check the source_id returned
        source_id = result.get('meta_source_id', 0)
        if int(source_id) == int(parent_id) and int(parent_id) > 0:
            score += 40
            subscores["correct_link"] = True
            feedback_parts.append("Linked to correct course (BIO101)")
        else:
            # This path is theoretically unreachable given the SQL in export.sh
            # unless export.sh logic changes.
            subscores["correct_link"] = False
            feedback_parts.append(f"Linked to wrong course ID: {source_id}")

        # Criterion 3: Method Enabled (10 pts)
        # status 0 = Enabled, 1 = Disabled
        status = int(result.get('meta_link_status', 1))
        if status == 0:
            score += 10
            subscores["enabled"] = True
            feedback_parts.append("Link is active")
        else:
            subscores["enabled"] = False
            feedback_parts.append("Link is disabled (hidden)")

        # Criterion 4: Students Synced (10 pts)
        test_synced = result.get('test_student_synced', False)
        current_enrollment = int(result.get('current_enrollment', 0))
        initial_enrollment = int(result.get('initial_enrollment', 0))

        if test_synced or (current_enrollment > initial_enrollment):
            score += 10
            subscores["synced"] = True
            feedback_parts.append(f"Enrollments synced (count: {current_enrollment})")
        else:
            subscores["synced"] = False
            feedback_parts.append("No students synced yet")

        passed = score >= 80

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - export may have failed"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON in result file: {str(e)}"}
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}