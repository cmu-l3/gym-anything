#!/usr/bin/env python3
"""Verifier for Reset Course Data task in Moodle."""

import json
import tempfile
import os
import logging
import time
from datetime import datetime, timezone

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_reset_course(traj, env_info, task_info):
    """
    Verify that the course was reset correctly.

    Criteria:
    1. Course Content Preserved: Modules count > 0 (Prevent course deletion) - CRITICAL
    2. Start Date Updated: Matches Sept 1, 2026 (approx timestamp)
    3. Student Unenrolled: jsmith is no longer enrolled
    4. Data Cleared: Submissions, Attempts, Posts count should be 0

    Scoring:
    - Date Correct: 20 pts
    - Student Unenrolled: 20 pts
    - Submissions Cleared: 20 pts
    - Attempts Cleared: 20 pts
    - Posts Cleared: 20 pts
    (Penalty if modules missing)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_start_date = metadata.get('expected_start_date_unix', 1788220800) # 2026-09-01
    
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        # Sanity Check: Course Exists
        if not result.get('course_exists', False):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "CRITICAL: Course BIO101 was not found. It may have been deleted instead of reset."
            }

        # CRITICAL: Content Preservation Check
        module_count = int(result.get('module_count', 0))
        if module_count == 0:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "CRITICAL: All course modules are missing. The course content was deleted or the wrong reset options were selected."
            }

        score = 0
        feedback_parts = []
        subscores = {}

        # 1. Check Start Date (20 pts)
        actual_date = int(result.get('start_date', 0))
        # Allow +/- 24 hours tolerance for timezone differences
        diff = abs(actual_date - expected_start_date)
        if diff < 86400:
            score += 20
            subscores['start_date'] = True
            feedback_parts.append("Start date updated correctly to Sept 1, 2026")
        else:
            subscores['start_date'] = False
            # Convert for friendly feedback
            try:
                actual_str = datetime.fromtimestamp(actual_date, tz=timezone.utc).strftime('%Y-%m-%d')
                expected_str = datetime.fromtimestamp(expected_start_date, tz=timezone.utc).strftime('%Y-%m-%d')
                feedback_parts.append(f"Start date incorrect. Expected ~{expected_str}, got {actual_str}")
            except:
                feedback_parts.append(f"Start date incorrect (Timestamp: {actual_date})")

        # 2. Check Student Unenrolled (20 pts)
        jsmith_enrolled = result.get('jsmith_enrolled', True)
        if not jsmith_enrolled:
            score += 20
            subscores['student_unenrolled'] = True
            feedback_parts.append("Student jsmith successfully unenrolled")
        else:
            subscores['student_unenrolled'] = False
            feedback_parts.append("Student jsmith is still enrolled")

        # 3. Check Data Cleared (60 pts total split 3 ways)
        # Submissions
        subs = int(result.get('submission_count', -1))
        if subs == 0:
            score += 20
            subscores['submissions_cleared'] = True
            feedback_parts.append("Assignment submissions cleared")
        else:
            feedback_parts.append(f"Assignments not cleared ({subs} remain)")

        # Attempts
        att = int(result.get('attempt_count', -1))
        if att == 0:
            score += 20
            subscores['attempts_cleared'] = True
            feedback_parts.append("Quiz attempts cleared")
        else:
            feedback_parts.append(f"Quiz attempts not cleared ({att} remain)")

        # Posts
        posts = int(result.get('post_count', -1))
        if posts == 0:
            score += 20
            subscores['posts_cleared'] = True
            feedback_parts.append("Forum posts cleared")
        else:
            feedback_parts.append(f"Forum posts not cleared ({posts} remain)")

        passed = score >= 80

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}