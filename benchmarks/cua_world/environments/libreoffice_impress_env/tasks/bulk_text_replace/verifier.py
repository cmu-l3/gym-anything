#!/usr/bin/env python3
"""
Verifier for Bulk Text Replace task.
Uses WHO Health Workforce Report data — replace "workforce" with "personnel".
"""

import sys
import os
import logging

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from impress_verification_utils import (
    copy_and_parse_presentation,
    get_slide_text_content,
    cleanup_verification_environment,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_text_replaced(traj, env_info, task_info):
    """
    Verify text replacement across WHO Health Workforce Report.

    Checks:
    1. Old text "workforce" is no longer present (case-insensitive)
    2. New text "personnel" is present
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Presentations/replace_test.odp"
    success, presentation, error, temp_dir = copy_and_parse_presentation(
        container_path,
        copy_from_env,
        file_format='odp'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": error}

    try:
        criteria_passed = 0
        total_criteria = 2
        feedback_parts = []

        # Collect all text from all slides
        all_text = []
        for i in range(presentation.get('slide_count', 0)):
            title, bullets = get_slide_text_content(presentation, i)
            if title:
                all_text.append(title)
            all_text.extend(bullets)

        combined_text = ' '.join(all_text)
        combined_lower = combined_text.lower()

        # Criterion 1: "workforce" should be gone
        workforce_count = combined_lower.count("workforce")
        if workforce_count == 0:
            criteria_passed += 1
            feedback_parts.append("Old text 'workforce' removed")
        else:
            feedback_parts.append(f"Old text 'workforce' still present ({workforce_count} instances)")

        # Criterion 2: "personnel" should be present
        personnel_count = combined_lower.count("personnel")
        if personnel_count >= 5:
            criteria_passed += 1
            feedback_parts.append(f"New text 'personnel' present ({personnel_count} instances)")
        else:
            feedback_parts.append(f"New text 'personnel' insufficient ({personnel_count} instances, need 5+)")

        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_environment(temp_dir)
