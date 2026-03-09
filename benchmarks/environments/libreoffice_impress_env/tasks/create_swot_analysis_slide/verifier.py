#!/usr/bin/env python3
"""
Verifier for create_swot_analysis_slide task.
"""

import json
import tempfile
import os
import logging
import sys

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from impress_verification_utils import (
    copy_and_parse_presentation,
    get_slide_count,
    cleanup_verification_environment,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_swot_analysis_slide(traj, env_info, task_info):
    """
    Verify that a SWOT analysis slide was added with correct content.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    presentation_path = metadata.get('presentation_path', '/home/ga/Documents/Presentations/renewable_energy_strategy.odp')
    required_keywords = metadata.get('sections', {})

    # Load result JSON
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}

    if not result_data.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Presentation file not found"}

    # Copy and parse ODP
    success, presentation, error, temp_dir = copy_and_parse_presentation(
        presentation_path,
        copy_from_env,
        file_format='odp'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse presentation: {error}"}

    score = 0
    feedback_parts = []
    
    try:
        # 1. Check Slide Count (10 pts)
        slide_count = get_slide_count(presentation)
        if slide_count >= 3:
            score += 10
            feedback_parts.append(f"✅ Slide count increased to {slide_count}")
        else:
            feedback_parts.append(f"❌ Slide count is {slide_count} (expected >= 3)")

        # 2. Find the SWOT slide
        # We search all slides for "SWOT" in the text
        swot_slide_index = -1
        swot_slide_text = ""
        
        slides = presentation.get('slides', [])
        for idx, slide in enumerate(slides):
            # Combine all text elements
            text_content = " ".join(slide.get('text_elements', [])).lower()
            if "swot" in text_content:
                swot_slide_index = idx
                swot_slide_text = text_content
                break
        
        # Fallback: if no "SWOT" found, check the last slide if count >= 3
        if swot_slide_index == -1 and slide_count >= 3:
            swot_slide_index = slide_count - 1
            swot_slide_text = " ".join(slides[swot_slide_index].get('text_elements', [])).lower()

        if swot_slide_index != -1:
            score += 10 # Found a candidate slide
            feedback_parts.append(f"✅ SWOT slide candidate found (Slide {swot_slide_index + 1})")
            
            # 3. Verify Title (10 pts)
            if "swot" in swot_slide_text and "renewable" in swot_slide_text:
                score += 10
                feedback_parts.append("✅ Title contains 'SWOT' and 'Renewable'")
            else:
                feedback_parts.append("⚠️ Title missing required keywords")

            # 4. Verify Quadrants Content (15 pts per quadrant = 60 pts)
            # We look for keywords defined in metadata
            
            sections_found = 0
            for section, keywords in required_keywords.items():
                hits = 0
                for kw in keywords:
                    if kw.lower() in swot_slide_text:
                        hits += 1
                
                # We need at least 2 keywords per section to count it as "good"
                if hits >= 2:
                    sections_found += 1
                    score += 15
                    feedback_parts.append(f"✅ {section.capitalize()} section verified")
                elif hits == 1:
                    score += 5 # Partial credit
                    feedback_parts.append(f"⚠️ {section.capitalize()} section incomplete")
                else:
                    feedback_parts.append(f"❌ {section.capitalize()} section missing")

        else:
            feedback_parts.append("❌ No slide found containing 'SWOT' content")

        # 5. Verify original slides preserved (10 pts)
        # Check Slide 1 for "Strategy" and Slide 2 for "Profile" or "Energy"
        if slide_count >= 2:
            s1_text = " ".join(slides[0].get('text_elements', [])).lower()
            s2_text = " ".join(slides[1].get('text_elements', [])).lower()
            
            if "strategy" in s1_text and "energy" in s2_text:
                score += 10
                feedback_parts.append("✅ Original slides preserved")
            else:
                feedback_parts.append("❌ Original slides appear modified")

        # Anti-gaming check: File modified
        if not result_data.get('file_modified'):
             feedback_parts.append("⚠️ File not modified during task (score capped)")
             score = min(score, 40)

        passed = score >= 60
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification logic error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification logic error: {str(e)}"}
        
    finally:
        cleanup_verification_environment(temp_dir)