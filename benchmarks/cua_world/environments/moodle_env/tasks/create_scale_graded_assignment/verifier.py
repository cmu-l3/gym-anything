#!/usr/bin/env python3
"""Verifier for Create Scale Graded Assignment task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_scale_graded_assignment(traj, env_info, task_info):
    """
    Verify creation of a custom scale and its usage in an assignment.

    Scoring (100 points):
    1. Scale exists with correct name (15 pts)
    2. Scale has correct values (20 pts)
    3. Assignment exists in course (15 pts)
    4. Assignment newly created (10 pts)
    5. Assignment configured to use a Scale (grade < 0) (20 pts)
    6. Assignment links to the CORRECT scale (20 pts)

    Pass threshold: 60 points (must have scale + assignment linked)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_scale_values = metadata.get('expected_scale_values', 'Not Yet Competent, Developing, Competent, Proficient, Expert')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_scale_graded_assignment_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # 1. Scale Exists (15 pts)
        scale_found = result.get('scale_found', False)
        scale_id = int(result.get('scale_id', 0))
        if scale_found and scale_id > 0:
            score += 15
            subscores['scale_exists'] = True
            feedback_parts.append("Scale created")
        else:
            subscores['scale_exists'] = False
            feedback_parts.append("Scale NOT found")

        # 2. Scale Values Correct (20 pts)
        actual_values = result.get('scale_values', '').strip()
        # Normalization for comparison (Moodle stores as comma-separated)
        # We allow minor spacing differences
        normalized_expected = [v.strip().lower() for v in expected_scale_values.split(',')]
        normalized_actual = [v.strip().lower() for v in actual_values.split(',')]

        if normalized_actual == normalized_expected:
            score += 20
            subscores['values_correct'] = True
            feedback_parts.append("Scale values correct")
        else:
            # Check for partial match (e.g. at least 3 correct values)
            common = set(normalized_actual).intersection(set(normalized_expected))
            if len(common) >= 3:
                score += 10
                subscores['values_correct'] = False
                feedback_parts.append(f"Scale values partially correct ({len(common)} matches)")
            else:
                subscores['values_correct'] = False
                feedback_parts.append(f"Scale values incorrect. Expected: {expected_scale_values}")

        # 3. Assignment Exists (15 pts)
        assign_found = result.get('assign_found', False)
        if assign_found:
            score += 15
            subscores['assign_exists'] = True
            feedback_parts.append("Assignment created")
        else:
            subscores['assign_exists'] = False
            feedback_parts.append("Assignment NOT found")

        # 4. Assignment Newly Created (10 pts)
        initial_assign = int(result.get('initial_assign_count', 0))
        current_assign = int(result.get('current_assign_count', 0))
        if assign_found and current_assign > initial_assign:
            score += 10
            subscores['newly_created'] = True
            feedback_parts.append("Assignment is new")
        else:
            subscores['newly_created'] = False
            if assign_found:
                feedback_parts.append("Assignment pre-existed")
            else:
                feedback_parts.append("Assignment not created")

        # 5. Assignment Uses Scale (20 pts)
        assign_uses_scale = result.get('assign_uses_scale', False)
        if assign_uses_scale:
            score += 20
            subscores['uses_scale'] = True
            feedback_parts.append("Assignment uses scale grading")
        else:
            subscores['uses_scale'] = False
            feedback_parts.append("Assignment does NOT use scale (likely points)")

        # 6. Assignment Links to Correct Scale (20 pts)
        assign_scale_id = int(result.get('assign_scale_id', 0))
        if assign_uses_scale and scale_found and assign_scale_id == scale_id:
            score += 20
            subscores['correct_scale_link'] = True
            feedback_parts.append("Assignment linked to correct scale")
        elif assign_uses_scale:
            subscores['correct_scale_link'] = False
            feedback_parts.append(f"Assignment linked to wrong scale (ID: {assign_scale_id}, Expected: {scale_id})")
        else:
            subscores['correct_scale_link'] = False

        passed = score >= 60 and subscores.get('scale_exists') and subscores.get('assign_exists')

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification failed: {str(e)}"
        }