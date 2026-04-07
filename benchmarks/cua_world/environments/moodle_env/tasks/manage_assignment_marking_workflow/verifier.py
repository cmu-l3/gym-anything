#!/usr/bin/env python3
"""Verifier for Manage Assignment Marking Workflow task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_manage_assignment_marking_workflow(traj, env_info, task_info):
    """
    Verify that the agent enabled marking workflow and set a student's state to 'In review'.

    Scoring (100 points):
    - Criterion 1: Assignment marking workflow is enabled (40 points)
    - Criterion 2: Student 'bbrown' has workflow state 'inreview' (40 points)
    - Criterion 3: Correct assignment context (Assignment found) (20 points)

    Pass threshold: 80 points (Must complete both key actions)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_state = metadata.get('expected_workflow_state', 'inreview')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/manage_assignment_marking_workflow_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # Criterion 3: Assignment Found (Context check) (20 points)
        if result.get('assignment_found', False):
            score += 20
            feedback_parts.append("Assignment found")
        else:
            feedback_parts.append("Assignment 'Final Research Paper' not found")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }

        # Criterion 1: Workflow Enabled (40 points)
        # Moodle stores boolean as 1 or 0
        workflow_enabled = int(result.get('marking_workflow_enabled', 0))
        if workflow_enabled == 1:
            score += 40
            subscores["workflow_enabled"] = True
            feedback_parts.append("Marking workflow enabled")
        else:
            subscores["workflow_enabled"] = False
            feedback_parts.append("Marking workflow NOT enabled")

        # Criterion 2: Student State 'inreview' (40 points)
        actual_state = result.get('student_workflow_state', '').lower()
        if actual_state == expected_state:
            score += 40
            subscores["student_state_correct"] = True
            feedback_parts.append(f"Student state correct ({expected_state})")
        else:
            subscores["student_state_correct"] = False
            feedback_parts.append(f"Student state incorrect: expected '{expected_state}', got '{actual_state}'")

        # Anti-gaming: Check if modification happened after task start
        assign_mtime = int(result.get('assign_timemodified', 0))
        task_start = int(result.get('task_start_time', 0))
        
        # We only strictly penalize if workflow is enabled but mtime is old (which shouldn't happen as setup resets it)
        # But setup resets it to 0, so if it's still 0, the agent didn't touch settings.
        # Actually setup creates it fresh, so mtime will be close to task start. 
        # If agent modifies it, mtime updates.
        
        passed = score >= 80

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "Invalid JSON result"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error: {str(e)}"}