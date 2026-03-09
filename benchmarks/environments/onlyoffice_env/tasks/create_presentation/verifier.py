#!/usr/bin/env python3
"""
Verifier for Create Presentation task
"""

import sys
import os
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    count_slides,
    get_slide_text,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_presentation(traj, env_info, task_info):
    """
    Verify that presentation was created correctly.

    Checks:
    1. Presentation has at least 2 slides
    2. First slide contains "Company Overview"
    3. Second slide contains "Key Achievements"
    4. Second slide contains bullet points (Revenue, Customers, Product)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Presentations/company_overview.pptx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_pres_')

    try:
        # Copy and parse the presentation
        success, prs, error = copy_and_parse_document(container_path, copy_from_env, 'pptx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load presentation: {error}"}

        criteria_passed = 0
        feedback_parts = []

        # Criterion 1: Check number of slides (should be at least 2)
        slide_count = count_slides(prs)
        if slide_count >= 2:
            criteria_passed += 1
            feedback_parts.append(f"✅ Presentation has {slide_count} slides")
        else:
            feedback_parts.append(f"❌ Presentation has only {slide_count} slide(s), expected at least 2")

        if slide_count < 2:
            # Cannot check further criteria
            return {
                "passed": False,
                "score": int((criteria_passed / 4) * 100),
                "feedback": " | ".join(feedback_parts)
            }

        # Criterion 2: Check first slide has "Company Overview"
        slide1_text = get_slide_text(prs, 0).lower()
        if "company overview" in slide1_text:
            criteria_passed += 1
            feedback_parts.append("✅ First slide contains 'Company Overview'")
        else:
            feedback_parts.append(f"❌ First slide missing 'Company Overview': {slide1_text[:50]}")

        # Criterion 3: Check second slide has "Key Achievements"
        slide2_text = get_slide_text(prs, 1).lower()
        if "key achievements" in slide2_text:
            criteria_passed += 1
            feedback_parts.append("✅ Second slide contains 'Key Achievements'")
        else:
            feedback_parts.append(f"❌ Second slide missing 'Key Achievements': {slide2_text[:50]}")

        # Criterion 4: Check second slide has bullet points content
        has_revenue = "revenue" in slide2_text and ("25" in slide2_text or "growth" in slide2_text)
        has_customers = "customer" in slide2_text and ("500" in slide2_text or "new" in slide2_text)
        has_product = "product" in slide2_text and ("3" in slide2_text or "launch" in slide2_text)

        bullet_count = sum([has_revenue, has_customers, has_product])

        if bullet_count >= 2:
            criteria_passed += 1
            feedback_parts.append(f"✅ Second slide has {bullet_count}/3 expected bullet points")
        else:
            feedback_parts.append(f"❌ Second slide missing bullet points ({bullet_count}/3 found)")

        score = int((criteria_passed / 4) * 100)
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
        cleanup_temp_dir(temp_dir)
