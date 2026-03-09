#!/usr/bin/env python3
"""
Verifier for Create Agenda Summary Slide task.

Verification Logic:
1. Parse the ODP file.
2. Check total slide count (should be 7, up from 6).
3. Check that Slide 2 (index 1) is the Agenda slide.
4. Verify Slide 2 contains the titles of Slides 3-7 in the correct order.
"""

import sys
import os
import json
import logging
import tempfile
from difflib import SequenceMatcher

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from impress_verification_utils import (
    copy_and_parse_presentation,
    get_slide_count,
    get_slide_title,
    get_slide_bullets,
    cleanup_verification_environment,
    get_slide_text_content
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def similar(a, b):
    """Check similarity between two strings."""
    return SequenceMatcher(None, a.lower(), b.lower()).ratio()

def verify_agenda_slide(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected metadata
    metadata = task_info.get('metadata', {})
    expected_count = metadata.get('expected_slide_count', 7)
    expected_topics = metadata.get('expected_topics', [])
    target_file = metadata.get('target_file', "/home/ga/Documents/Presentations/strategic_initiatives.odp")

    # Load result JSON from export script
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}

    # Check if file was modified
    if not task_result.get("file_modified", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Presentation file was not modified (did you save?)."
        }

    # Copy and parse presentation
    success, presentation, error, temp_dir = copy_and_parse_presentation(
        target_file,
        copy_from_env,
        file_format='odp'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse presentation: {error}"}

    try:
        score = 0
        feedback_parts = []
        
        # 1. Check Slide Count (10 pts)
        actual_count = get_slide_count(presentation)
        if actual_count == expected_count:
            score += 10
            feedback_parts.append("✅ Correct slide count (7)")
        else:
            feedback_parts.append(f"❌ Incorrect slide count: {actual_count} (expected {expected_count})")

        # 2. Check Agenda Slide Position and Title (30 pts)
        # Agenda should be at index 1 (Slide 2)
        agenda_slide_idx = 1
        agenda_title = get_slide_title(presentation, agenda_slide_idx) or ""
        
        if "agenda" in agenda_title.lower() or "summary" in agenda_title.lower() or "contents" in agenda_title.lower():
            score += 30
            feedback_parts.append(f"✅ Agenda slide found at correct position (Title: '{agenda_title}')")
        else:
            # Fallback: check if it's at index 0 or 2 just in case
            feedback_parts.append(f"❌ Slide 2 title '{agenda_title}' does not look like an Agenda")
            # Minimal partial credit if they put it somewhere else? No, strict on position.

        # 3. Check Content (60 pts)
        # We expect the bullets on Slide 2 to match the expected topics
        agenda_bullets = get_slide_bullets(presentation, agenda_slide_idx)
        
        # Clean bullets (remove empty strings)
        agenda_bullets = [b for b in agenda_bullets if b.strip()]
        
        # Also check slide text content broadly in case they didn't use bullets but text boxes
        _, all_text_list = get_slide_text_content(presentation, agenda_slide_idx)
        all_text_blob = " ".join(all_text_list).lower()

        matches = 0
        ordered_matches = 0
        last_match_index = -1
        
        for i, topic in enumerate(expected_topics):
            topic_found = False
            
            # Strict check in bullets
            for bullet in agenda_bullets:
                if similar(bullet, topic) > 0.8 or topic.lower() in bullet.lower():
                    topic_found = True
                    break
            
            # Loose check in full text
            if not topic_found and topic.lower() in all_text_blob:
                topic_found = True

            if topic_found:
                matches += 1
                # Check order: finding position in text
                curr_index = all_text_blob.find(topic.lower())
                if curr_index > last_match_index:
                    ordered_matches += 1
                    last_match_index = curr_index
        
        # Scoring logic for content
        # 5 topics * 8 pts each = 40 pts for presence
        # 5 topics * 4 pts each = 20 pts for order
        
        presence_score = (matches / len(expected_topics)) * 40
        order_score = (ordered_matches / len(expected_topics)) * 20
        
        score += int(presence_score + order_score)
        
        feedback_parts.append(f"✅ Found {matches}/{len(expected_topics)} topics")
        if matches == len(expected_topics) and ordered_matches == matches:
            feedback_parts.append("✅ Topics in correct order")
        elif matches > 0:
            feedback_parts.append(f"⚠️ {ordered_matches}/{matches} topics in correct order")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification logic error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_environment(temp_dir)