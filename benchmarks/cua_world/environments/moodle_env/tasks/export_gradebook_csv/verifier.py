#!/usr/bin/env python3
"""Verifier for Export Gradebook CSV task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_export_gradebook_csv(traj, env_info, task_info):
    """
    Verify that the gradebook was exported correctly to CSV with feedback.

    Scoring (100 points):
    - File exists at correct path: 20 pts
    - File has content (>100 bytes): 10 pts
    - File created/modified during task: 10 pts
    - Correct Grade Item Header found (Lab Safety Quiz): 20 pts
    - Verification Token found (Feedback included): 40 pts

    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/export_gradebook_csv_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        # Criterion 1: File Existence (20 pts)
        if result.get('file_exists', False):
            score += 20
            feedback_parts.append("File found at correct location")
        else:
            feedback_parts.append("File NOT found at ~/Documents/BIO101_Grades.csv")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }

        # Criterion 2: File Size (10 pts)
        size = result.get('file_size', 0)
        if size > 100:
            score += 10
            feedback_parts.append("File is not empty")
        else:
            feedback_parts.append("File appears empty")

        # Criterion 3: Timestamp (10 pts)
        if result.get('created_during_task', False):
            score += 10
            feedback_parts.append("File created during task")
        else:
            feedback_parts.append("File timestamp is old (pre-task)")

        # Criterion 4: Header Check (20 pts)
        if result.get('header_found', False):
            score += 20
            feedback_parts.append("Grade item header found")
        else:
            feedback_parts.append("Grade item 'Lab Safety Quiz' not found in file")

        # Criterion 5: Token Check - CRITICAL for feedback verification (40 pts)
        if result.get('token_found', False):
            score += 40
            feedback_parts.append("Feedback verification token found (Feedback included)")
        else:
            feedback_parts.append("Feedback token MISSING. Did you check 'Include feedback' in export settings?")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}