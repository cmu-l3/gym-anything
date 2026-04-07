#!/usr/bin/env python3
"""Verifier for Configure Activity Groupings task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_activity_groupings(traj, env_info, task_info):
    """
    Verify creation of Grouping 'Lab Sections' with correct groups and Assignment 'Lab Report 1' restricted to it.

    Scoring (100 points):
    - 'Lab Sections' grouping created (20 pts)
    - 'Monday Lab' in grouping (15 pts)
    - 'Thursday Lab' in grouping (15 pts)
    - 'Lab Report 1' assignment created (20 pts)
    - Assignment restricted to correct grouping (20 pts)
    - Assignment group mode set (Separate/Visible) (10 pts)

    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/configure_activity_groupings_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # 1. Grouping Creation (20 pts)
        if result.get("grouping_exists", False):
            score += 20
            feedback_parts.append("Grouping 'Lab Sections' created")
            if result.get("grouping_created_during_task", False):
                feedback_parts.append("(newly created)")
        else:
            feedback_parts.append("Grouping 'Lab Sections' NOT found")

        # 2. Group Membership (30 pts total)
        if result.get("monday_lab_included", False):
            score += 15
            feedback_parts.append("Monday Lab added")
        else:
            feedback_parts.append("Monday Lab missing from grouping")
            
        if result.get("thursday_lab_included", False):
            score += 15
            feedback_parts.append("Thursday Lab added")
        else:
            feedback_parts.append("Thursday Lab missing from grouping")

        # 3. Assignment Creation (20 pts)
        if result.get("assignment_exists", False):
            score += 20
            feedback_parts.append("Assignment created")
        else:
            feedback_parts.append("Assignment 'Lab Report 1' NOT found")

        # 4. Assignment Configuration (30 pts total)
        if result.get("assignment_grouping_correct", False):
            score += 20
            feedback_parts.append("Assignment correctly restricted to grouping")
        else:
            feedback_parts.append("Assignment NOT linked to correct grouping")
            
        if result.get("assignment_groupmode_correct", False):
            score += 10
            feedback_parts.append("Group mode enabled")
        else:
            feedback_parts.append("Group mode NOT set to Separate/Visible")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": result
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "Invalid JSON in result file"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}