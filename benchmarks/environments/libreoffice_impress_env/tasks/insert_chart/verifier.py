#!/usr/bin/env python3
"""
Verifier for Insert Chart task
"""

import sys
import os
import logging

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from impress_verification_utils import (
    copy_and_parse_presentation,
    check_slide_has_chart,
    cleanup_verification_environment,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_chart_inserted(traj, env_info, task_info):
    """
    Verify chart insertion.
    
    Checks:
    1. Chart object exists on slide
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    container_path = "/home/ga/Documents/Presentations/chart_test.odp"
    success, presentation, error, temp_dir = copy_and_parse_presentation(
        container_path,
        copy_from_env,
        file_format='odp'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": error}

    try:
        feedback_parts = []
        
        # Check for chart on first slide
        has_chart = check_slide_has_chart(presentation, 0)
        
        if has_chart:
            feedback_parts.append("✅ Chart detected on slide")
            score = 100
            passed = True
        else:
            feedback_parts.append("❌ No chart found on slide")
            score = 0
            passed = False
        
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
