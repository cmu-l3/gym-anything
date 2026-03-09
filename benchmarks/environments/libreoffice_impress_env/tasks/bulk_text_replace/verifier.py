#!/usr/bin/env python3
"""
Verifier for Bulk Text Replace task
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
    Verify text replacement.
    
    Checks:
    1. Old text "Company" is no longer present
    2. New text "Organization" is present
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
        
        # Criterion 1: "Company" should be gone or mostly gone
        company_count = combined_text.count("Company")
        if company_count == 0:
            criteria_passed += 1
            feedback_parts.append("✅ Old text 'Company' removed")
        else:
            feedback_parts.append(f"❌ Old text 'Company' still present ({company_count} instances)")
        
        # Criterion 2: "Organization" should be present
        organization_count = combined_text.count("Organization")
        if organization_count >= 2:
            criteria_passed += 1
            feedback_parts.append(f"✅ New text 'Organization' present ({organization_count} instances)")
        else:
            feedback_parts.append(f"❌ New text 'Organization' not found or insufficient ({organization_count} instances)")
        
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
