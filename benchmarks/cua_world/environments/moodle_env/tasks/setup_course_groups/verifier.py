#!/usr/bin/env python3
"""Verifier for Setup Course Groups task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_setup_course_groups(traj, env_info, task_info):
    """
    Verify that course groups were created in HIST201 with correct members
    and course group mode set.

    Scoring (100 points):
    - Criterion 1: Discussion Group A exists in HIST201 (15 points)
    - Criterion 2: Discussion Group B exists in HIST201 (15 points)
    - Criterion 3: Correct members in Group A - bbrown and cgarcia (25 points)
    - Criterion 4: Correct member in Group B - dlee (20 points)
    - Criterion 5: Course group mode set to Separate groups (25 points)

    Pass threshold: 70 points (must have both groups created)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/setup_course_groups_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # Baseline check - were new groups actually created?
        initial_count = int(result.get('initial_group_count', 0))
        current_count = int(result.get('current_group_count', 0))
        if current_count <= initial_count:
            feedback_parts.append(f"No new groups created (count: {initial_count} -> {current_count})")

        # Criterion 1: Discussion Group A exists (15 points)
        if result.get('group_a_found', False):
            score += 15
            subscores["group_a_exists"] = True
            feedback_parts.append("Discussion Group A created")
        else:
            subscores["group_a_exists"] = False
            feedback_parts.append("Discussion Group A not found")

        # Criterion 2: Discussion Group B exists (15 points)
        if result.get('group_b_found', False):
            score += 15
            subscores["group_b_exists"] = True
            feedback_parts.append("Discussion Group B created")
        else:
            subscores["group_b_exists"] = False
            feedback_parts.append("Discussion Group B not found")

        # Criterion 3: Correct members in Group A (25 points)
        bbrown_ok = result.get('bbrown_in_group_a', False)
        cgarcia_ok = result.get('cgarcia_in_group_a', False)
        if bbrown_ok and cgarcia_ok:
            score += 25
            subscores["group_a_members"] = True
            feedback_parts.append("Group A members correct (bbrown + cgarcia)")
        elif bbrown_ok or cgarcia_ok:
            score += 12
            subscores["group_a_members"] = False
            member = "bbrown" if bbrown_ok else "cgarcia"
            missing = "cgarcia" if bbrown_ok else "bbrown"
            feedback_parts.append(f"Group A partial: {member} added, {missing} missing")
        else:
            subscores["group_a_members"] = False
            feedback_parts.append("Group A members not assigned")

        # Criterion 4: Correct member in Group B (20 points)
        if result.get('dlee_in_group_b', False):
            score += 20
            subscores["group_b_members"] = True
            feedback_parts.append("Group B member correct (dlee)")
        else:
            subscores["group_b_members"] = False
            feedback_parts.append("dlee not in Group B")

        # Criterion 5: Course group mode (25 points)
        # Moodle: 0=No groups, 1=Separate groups, 2=Visible groups
        groupmode = int(result.get('course_groupmode', 0))
        if groupmode == 1:
            score += 25
            subscores["separate_groups"] = True
            feedback_parts.append("Course set to Separate groups")
        elif groupmode == 2:
            # Visible groups is a reasonable alternative - partial credit
            score += 15
            subscores["separate_groups"] = False
            feedback_parts.append("Course set to Visible groups (expected Separate)")
        else:
            subscores["separate_groups"] = False
            feedback_parts.append("Course group mode not changed (still No groups)")

        passed = (score >= 70
                  and subscores.get("group_a_exists", False)
                  and subscores.get("group_b_exists", False))

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
