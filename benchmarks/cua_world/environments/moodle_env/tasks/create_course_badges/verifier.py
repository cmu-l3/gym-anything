#!/usr/bin/env python3
"""Verifier for Create Course Badges task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_course_badges(traj, env_info, task_info):
    """
    Verify that two course badges were created with specific criteria.

    Scoring (100 points):
    - Badge 1 "Lab Safety Certified" exists in BIO101 (20 points)
    - Badge 2 "Biology Course Complete" exists in BIO101 (20 points)
    - Badge 1 has Manual Issue criteria by Teacher (20 points)
    - Badge 2 has Course Completion criteria (20 points)
    - Both badges are Enabled/Active (20 points)

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_course_badges_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # Parse Badge 1 Data
        b1 = result.get('badge1', {})
        b1_found = b1.get('found', False)
        b1_status = int(b1.get('status', 0))
        b1_type = int(b1.get('criteria_type', 0))
        b1_role = b1.get('role_param', '').lower()

        # Parse Badge 2 Data
        b2 = result.get('badge2', {})
        b2_found = b2.get('found', False)
        b2_status = int(b2.get('status', 0))
        b2_type = int(b2.get('criteria_type', 0))

        # Criterion 1: Badge 1 Exists (20 pts)
        if b1_found:
            score += 20
            subscores['badge1_exists'] = True
            feedback_parts.append("Badge 'Lab Safety Certified' found")
        else:
            subscores['badge1_exists'] = False
            feedback_parts.append("Badge 'Lab Safety Certified' NOT found")

        # Criterion 2: Badge 2 Exists (20 pts)
        if b2_found:
            score += 20
            subscores['badge2_exists'] = True
            feedback_parts.append("Badge 'Biology Course Complete' found")
        else:
            subscores['badge2_exists'] = False
            feedback_parts.append("Badge 'Biology Course Complete' NOT found")

        # Criterion 3: Badge 1 Criteria (Manual Issue by Teacher) (20 pts)
        # Type 2 = Manual issue. Role should be 'editingteacher' or 'teacher'
        if b1_found:
            if b1_type == 2:
                if 'teacher' in b1_role:
                    score += 20
                    subscores['badge1_criteria'] = True
                    feedback_parts.append("Badge 1 criteria correct (Manual by Teacher)")
                else:
                    score += 10 # Partial credit for correct type but wrong role
                    subscores['badge1_criteria'] = False
                    feedback_parts.append(f"Badge 1 role incorrect: expected teacher, got '{b1_role}'")
            else:
                subscores['badge1_criteria'] = False
                feedback_parts.append(f"Badge 1 criteria type incorrect: {b1_type} (expected Manual/2)")

        # Criterion 4: Badge 2 Criteria (Course Completion) (20 pts)
        # Type 4 = Course completion
        if b2_found:
            if b2_type == 4:
                score += 20
                subscores['badge2_criteria'] = True
                feedback_parts.append("Badge 2 criteria correct (Course Completion)")
            else:
                subscores['badge2_criteria'] = False
                feedback_parts.append(f"Badge 2 criteria type incorrect: {b2_type} (expected Course Complete/4)")

        # Criterion 5: Status (Both Enabled) (20 pts)
        # Status 1=active, 2=active+locked (both mean enabled)
        # Status 0=inactive, 3=inactive+locked
        b1_active = b1_status in [1, 2]
        b2_active = b2_status in [1, 2]

        if b1_active and b2_active:
            score += 20
            feedback_parts.append("Both badges enabled")
        elif b1_active or b2_active:
            score += 10
            feedback_parts.append("One badge enabled, one disabled")
        else:
            feedback_parts.append("Badges are disabled (Enable Access not clicked)")

        # Calculate pass status
        # Must have at least 60 points AND both badges found
        passed = (score >= 60 and b1_found and b2_found)

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON: {str(e)}"}
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}