#!/usr/bin/env python3
"""
Verifier for create_presentation_from_outline task.
"""

import sys
import os
import json
import logging
import tempfile
from typing import Dict, Any

# Add utils to path to import impress_verification_utils
# Assuming standard structure: /workspace/utils/impress_verification_utils.py
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
try:
    from impress_verification_utils import (
        copy_and_parse_presentation,
        get_slide_count,
        get_slide_title,
        get_slide_bullets,
        cleanup_verification_environment,
    )
except ImportError:
    # Fallback for local testing or if path differs
    logging.warning("Could not import impress_verification_utils, functionality will be limited")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_presentation_from_outline(traj, env_info, task_info):
    """
    Verify that the presentation was created correctly from the outline.
    
    Criteria:
    1. File exists and is a valid ODP (10 pts)
    2. File was created during the task (Anti-gaming check)
    3. Slide count is exactly 4 (30 pts)
    4. Slide titles match the outline (40 pts)
    5. Bullet points contain expected keywords (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/Presentations/ethics_lecture.odp')
    expected_titles = metadata.get('expected_titles', [])
    content_keywords = metadata.get('content_keywords', {})

    # 1. Get Export Result (Basic file checks)
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            export_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load export result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not export_result.get('output_exists'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "❌ Output file 'ethics_lecture.odp' not found."
        }
    
    if not export_result.get('file_created_during_task'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "❌ File was not modified during the task duration."
        }

    # 2. Parse ODP File
    success, presentation, error, temp_dir = copy_and_parse_presentation(
        expected_path,
        copy_from_env,
        file_format='odp'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"❌ Failed to parse presentation: {error}"}

    try:
        score = 10 # Base score for valid file
        feedback_parts = ["✅ Valid ODP file created"]
        
        # Criterion: Slide Count (30 pts)
        slide_count = get_slide_count(presentation)
        if slide_count == 4:
            score += 30
            feedback_parts.append(f"✅ Correct slide count ({slide_count})")
        else:
            feedback_parts.append(f"❌ Incorrect slide count: {slide_count} (expected 4)")

        # Criterion: Titles (40 pts)
        # We need to map found titles to expected titles to handle potential ordering issues,
        # though Outline View usually preserves order.
        found_titles = []
        for i in range(slide_count):
            t = get_slide_title(presentation, i)
            if t:
                found_titles.append(t.strip())
            else:
                found_titles.append("")

        correct_titles = 0
        for expected in expected_titles:
            # Case-insensitive partial match
            if any(expected.lower() in found.lower() for found in found_titles):
                correct_titles += 1
        
        title_score = int((correct_titles / len(expected_titles)) * 40) if expected_titles else 0
        score += title_score
        
        if correct_titles == len(expected_titles):
            feedback_parts.append("✅ All titles correct")
        else:
            feedback_parts.append(f"⚠️ {correct_titles}/{len(expected_titles)} titles correct")

        # Criterion: Content Keywords (20 pts)
        # Check specific slides for keywords
        keywords_found = 0
        total_keyword_groups = len(content_keywords)
        
        for slide_name, keywords in content_keywords.items():
            # Find the slide with this title
            target_slide_idx = -1
            for idx, title in enumerate(found_titles):
                if slide_name.lower() in title.lower():
                    target_slide_idx = idx
                    break
            
            if target_slide_idx != -1:
                bullets = get_slide_bullets(presentation, target_slide_idx)
                bullet_text = " ".join(bullets).lower()
                # Check if at least one keyword for this section is present in bullets
                if any(k.lower() in bullet_text for k in keywords):
                    keywords_found += 1
        
        content_score = int((keywords_found / total_keyword_groups) * 20) if total_keyword_groups else 0
        score += content_score
        
        if keywords_found == total_keyword_groups:
            feedback_parts.append("✅ Content structure verified")
        else:
            feedback_parts.append(f"⚠️ Content incomplete ({keywords_found}/{total_keyword_groups} sections matched)")

        # Final Pass Check
        # Must have at least 4 slides and correct titles to pass
        passed = (slide_count == 4) and (correct_titles >= 3) and (score >= 70)

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": {
                "found_titles": found_titles,
                "slide_count": slide_count
            }
        }

    except Exception as e:
        logger.error(f"Verification logic error: {e}", exc_info=True)
        return {"passed": False, "score": score, "feedback": f"Verification error: {e}"}
    
    finally:
        cleanup_verification_environment(temp_dir)