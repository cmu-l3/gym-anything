#!/usr/bin/env python3
"""Verifier for Log Student Behavioral Note task in Moodle."""

import json
import tempfile
import os
import logging
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_log_student_behavioral_note(traj, env_info, task_info):
    """
    Verify that a behavioral note was created for the correct student.

    Scoring (100 points):
    - Criterion 1: Note exists for correct student and created during task (30 points)
    - Criterion 2: Note is linked to correct course (HIST201) (20 points)
    - Criterion 3: Context is set to 'Course' (not Personal or Site) (25 points)
    - Criterion 4: Content contains key phrases (25 points)

    Pass threshold: 75 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_keywords = metadata.get('expected_content_keywords', ['talking', 'guest lecture', 'detention'])

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/log_note_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        note_found = result.get('note_found', False)
        note_content = result.get('note_content', '').lower()
        publish_state = result.get('publish_state', '').lower()
        
        # Criterion 1: Note exists (30 points)
        if note_found:
            score += 30
            subscores["note_created"] = True
            feedback_parts.append("Note created for student")
        else:
            feedback_parts.append("No note found created during task session")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": {"note_created": False}
            }

        # Criterion 2: Linked to correct course (20 points)
        # The query in export_result.sh filters by courseid, so if note_found is true,
        # it matched the course ID.
        if note_found:
            score += 20
            subscores["correct_course"] = True
            feedback_parts.append("Note linked to correct course")

        # Criterion 3: Context is 'Course' (25 points)
        # publishstate: 'personal', 'course', 'site'
        if publish_state == 'course':
            score += 25
            subscores["correct_context"] = True
            feedback_parts.append("Context: Course (Correct)")
        else:
            subscores["correct_context"] = False
            feedback_parts.append(f"Context incorrect: '{publish_state}' (expected 'course')")

        # Criterion 4: Content check (25 points)
        # Check for keywords
        found_keywords = [k for k in expected_keywords if k.lower() in note_content]
        if len(found_keywords) >= 2:
            score += 25
            subscores["content_accurate"] = True
            feedback_parts.append("Content accurate")
        elif len(found_keywords) == 1:
            score += 10
            subscores["content_accurate"] = False
            feedback_parts.append("Content partially accurate")
        else:
            subscores["content_accurate"] = False
            feedback_parts.append("Content missing key details")

        passed = score >= 75

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