#!/usr/bin/env python3
"""
Verifier for Create Basic Presentation task
"""

import sys
import os
import logging

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from impress_verification_utils import (
    copy_and_parse_presentation,
    get_slide_count,
    get_slide_title,
    get_slide_bullets,
    cleanup_verification_environment,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_basic_presentation(traj, env_info, task_info):
    """
    Verify basic presentation creation task.
    
    Checks:
    1. Presentation has exactly 5 slides
    2. Each slide has a title
    3. Each slide has at least 2 bullet points
    4. Content is relevant to the topic
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse presentation
    container_path = "/home/ga/Documents/Presentations/basic_presentation.odp"
    success, presentation, error, temp_dir = copy_and_parse_presentation(
        container_path,
        copy_from_env,
        file_format='odp'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": error}

    try:
        criteria_passed = 0
        total_criteria = 4
        feedback_parts = []

        # Criterion 1: Slide count (5 slides)
        slide_count = get_slide_count(presentation)
        if slide_count == 5:
            criteria_passed += 1
            feedback_parts.append(f"✅ Correct slide count: {slide_count}")
        else:
            feedback_parts.append(f"❌ Wrong slide count: expected 5, got {slide_count}")

        # Criterion 2: All slides have titles
        titles_present = 0
        for i in range(min(slide_count, 5)):
            title = get_slide_title(presentation, i)
            if title and len(title.strip()) > 0:
                titles_present += 1
        
        if titles_present >= 4:  # Allow 1 missing title
            criteria_passed += 1
            feedback_parts.append(f"✅ Titles present: {titles_present}/5 slides")
        else:
            feedback_parts.append(f"❌ Insufficient titles: {titles_present}/5 slides")

        # Criterion 3: All slides have bullet points (at least 2 each)
        slides_with_bullets = 0
        for i in range(min(slide_count, 5)):
            bullets = get_slide_bullets(presentation, i)
            if len(bullets) >= 2:
                slides_with_bullets += 1
        
        if slides_with_bullets >= 4:  # Allow 1 slide with fewer bullets
            criteria_passed += 1
            feedback_parts.append(f"✅ Bullet points present: {slides_with_bullets}/5 slides have 2+ bullets")
        else:
            feedback_parts.append(f"❌ Insufficient bullet points: only {slides_with_bullets}/5 slides have 2+ bullets")

        # Criterion 4: Content relevance (basic check)
        # Check if slides have meaningful content (not empty or placeholder text)
        meaningful_content_count = 0
        for i in range(min(slide_count, 5)):
            title = get_slide_title(presentation, i)
            bullets = get_slide_bullets(presentation, i)
            
            # Check if content is not placeholder
            if title and len(title.strip()) > 0 and title.lower() not in ['title', 'slide title', 'untitled']:
                if bullets and any(len(b.strip()) > 5 for b in bullets):
                    meaningful_content_count += 1
        
        if meaningful_content_count >= 4:
            criteria_passed += 1
            feedback_parts.append(f"✅ Meaningful content: {meaningful_content_count}/5 slides")
        else:
            feedback_parts.append(f"❌ Insufficient content: only {meaningful_content_count}/5 slides have meaningful content")

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "slide_count": slide_count == 5,
                "titles_present": titles_present >= 4,
                "bullets_present": slides_with_bullets >= 4,
                "meaningful_content": meaningful_content_count >= 4
            }
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_environment(temp_dir)
