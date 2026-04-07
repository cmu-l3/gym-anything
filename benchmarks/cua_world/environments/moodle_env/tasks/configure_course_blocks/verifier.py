#!/usr/bin/env python3
"""Verifier for Configure Course Blocks task in Moodle."""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_course_blocks(traj, env_info, task_info):
    """
    Verify that Calendar and Text blocks are correctly configured in HIST201.

    Scoring (100 points):
    - Criterion 1: Calendar block exists in HIST201 (30 points)
    - Criterion 2: A Text (HTML) block exists in HIST201 (30 points)
    - Criterion 3: Text block title is 'Course Support' (20 points)
    - Criterion 4: Text block content contains 'help@history.edu' (20 points)

    Pass threshold: 80 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('html_block_title', 'Course Support').lower()
    expected_content_part = metadata.get('html_block_content', 'help@history.edu').lower()

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/configure_course_blocks_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # Criterion 1: Calendar block exists (30 points)
        if result.get('calendar_exists', False):
            score += 30
            subscores["calendar_exists"] = True
            feedback_parts.append("Calendar block found")
        else:
            subscores["calendar_exists"] = False
            feedback_parts.append("Calendar block NOT found")

        # Process HTML blocks
        html_blocks = result.get('html_blocks', [])
        html_block_found = len(html_blocks) > 0
        
        # Criterion 2: HTML block exists (30 points)
        if html_block_found:
            score += 30
            subscores["html_block_exists"] = True
            feedback_parts.append("Text block found")
        else:
            subscores["html_block_exists"] = False
            feedback_parts.append("Text block NOT found")

        # Criterion 3 & 4: Check content of HTML blocks
        # We search for ANY block that satisfies the conditions
        title_correct = False
        content_correct = False
        
        best_block_feedback = []

        for block in html_blocks:
            b_title = block.get('title', '').strip().lower()
            b_text = block.get('text', '').strip().lower()
            
            # Check title (case-insensitive)
            this_title_ok = expected_title in b_title
            
            # Check content (substring match)
            this_content_ok = expected_content_part in b_text
            
            if this_title_ok and this_content_ok:
                title_correct = True
                content_correct = True
                break # Found a perfect match
            
            # Keep looking, but track if we found partial matches
            if this_title_ok: title_correct = True
            if this_content_ok: content_correct = True

        # Score Title (20 points)
        if title_correct:
            score += 20
            subscores["title_correct"] = True
            feedback_parts.append(f"Text block title correct ('{expected_title}')")
        elif html_block_found:
            subscores["title_correct"] = False
            feedback_parts.append("Text block title mismatch")

        # Score Content (20 points)
        if content_correct:
            score += 20
            subscores["content_correct"] = True
            feedback_parts.append(f"Text block content correct (contains '{expected_content_part}')")
        elif html_block_found:
            subscores["content_correct"] = False
            feedback_parts.append("Text block content mismatch")

        passed = score >= 80

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - export may have failed"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON in result file: {str(e)}"}
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}