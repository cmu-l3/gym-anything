#!/usr/bin/env python3
"""Verifier for Configure Course Completion Logic task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_course_completion_logic(traj, env_info, task_info):
    """
    Verify course completion logic configuration.

    Scoring (100 points):
    1. Quiz "Grade to pass" set to 80.00 (20 pts)
    2. Quiz completion requires passing grade (20 pts)
    3. Handbook completion requires view (20 pts)
    4. Course completion criteria includes both activities (20 pts)
    5. Course completion aggregation is ALL (20 pts)

    Pass threshold: 80 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_gradepass = float(metadata.get('target_gradepass', 80.00))

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/course_completion_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # 1. Check Grade to Pass (20 pts)
        gradepass = float(result.get('quiz_gradepass', 0))
        # Allow small floating point tolerance (0.01)
        if abs(gradepass - target_gradepass) < 0.01:
            score += 20
            subscores['gradepass'] = True
            feedback_parts.append(f"Quiz grade to pass set to {gradepass}")
        else:
            subscores['gradepass'] = False
            feedback_parts.append(f"Quiz grade to pass mismatch: {gradepass} (expected {target_gradepass})")

        # 2. Check Quiz Completion Rules (20 pts)
        # completion_mode: 2 = auto
        # req_passgrade: 1 = enabled
        quiz_mode = int(result.get('quiz_completion_mode', 0))
        quiz_pass = int(result.get('quiz_req_passgrade', 0))
        
        if quiz_mode == 2 and quiz_pass == 1:
            score += 20
            subscores['quiz_completion'] = True
            feedback_parts.append("Quiz completion requires passing grade")
        elif quiz_mode != 2:
            feedback_parts.append("Quiz completion not set to Auto")
        else:
            feedback_parts.append("Quiz completion does not require passing grade")

        # 3. Check Handbook Completion Rules (20 pts)
        # req_view: 1 = enabled
        handbook_mode = int(result.get('handbook_completion_mode', 0))
        handbook_view = int(result.get('handbook_req_view', 0))
        
        if handbook_mode == 2 and handbook_view == 1:
            score += 20
            subscores['handbook_completion'] = True
            feedback_parts.append("Handbook completion requires view")
        else:
            feedback_parts.append("Handbook completion not configured correctly (Require view missing or not Auto)")

        # 4. Check Course Completion Criteria (20 pts)
        # Must have both criteria
        quiz_crit = result.get('criteria_quiz_exists', False)
        handbook_crit = result.get('criteria_handbook_exists', False)
        
        if quiz_crit and handbook_crit:
            score += 20
            subscores['criteria_exists'] = True
            feedback_parts.append("Course completion criteria includes both activities")
        elif quiz_crit or handbook_crit:
            score += 10
            feedback_parts.append("Course completion criteria missing one activity")
        else:
            feedback_parts.append("No course completion criteria found for these activities")

        # 5. Check Aggregation Method (20 pts)
        # method: 1 = ALL, 2 = ANY
        # Note: If method is 0 or missing, it defaults to ALL usually, but we check specific setting if possible.
        # However, if criteria exist and method is 0/null, Moodle often implies ALL for the 'Activity completion' condition group.
        # Let's strict check for 1.
        aggr = int(result.get('aggregation_method', 0))
        
        if aggr == 1:
            score += 20
            subscores['aggregation'] = True
            feedback_parts.append("Aggregation method set to ALL")
        elif aggr == 2:
             feedback_parts.append("Aggregation method set to ANY (Expected ALL)")
        else:
            # If criteria exist but no explicit aggregation row for type 4, it often means default.
            # But in the UI, saving "ALL" usually writes a 1.
            # Give partial credit if criteria exists but aggregation ambiguous? No, stick to explicit.
            feedback_parts.append(f"Aggregation method undefined or unknown ({aggr})")

        passed = score >= 80

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}