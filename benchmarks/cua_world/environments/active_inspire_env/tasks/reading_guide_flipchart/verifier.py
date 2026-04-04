#!/usr/bin/env python3
"""
Verifier for reading_guide_flipchart task.

Scoring (100 points, pass at 70):
  Criterion 1: File exists + valid flipchart format        — 15 pts
  Criterion 2: Page count == 4                             — 15 pts
  Criterion 3: "Charlotte" (book/character) text present   — 15 pts
  Criterion 4: "Wilbur" character text present             — 15 pts
  Criterion 5: "Fern" character text present               — 10 pts
  Criterion 6: "Comprehension"/"Questions" text present    — 10 pts
  Criterion 7: Rectangle shapes >= 3 (character boxes)     — 15 pts
  Criterion 8: "Theme"/"Message" text present              —  5 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_reading_guide_flipchart(traj, env_info, task_info):
    """
    Verify the Charlotte's Web reading comprehension guide flipchart.
    Checks 4 pages with character names, comprehension section, and character boxes.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No copy_from_env function available"
        }

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()
        try:
            copy_from_env('/tmp/task_result.json', tmp_path)
            with open(tmp_path, 'r', encoding='utf-8-sig') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read export result: {e}"
        }

    score = 0
    feedback_parts = []
    subscores = {}

    # GATE: file must exist
    if not result.get('file_found'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target file not found: charlottes_web_guide.flipchart was not created"
        }

    # Criterion 1: File exists + valid format (15 pts)
    try:
        file_valid = result.get('file_valid', False)
        file_size = result.get('file_size', 0)
        if file_valid and file_size > 0:
            score += 15
            feedback_parts.append("Valid flipchart file created (15/15)")
            subscores['file_valid'] = True
        elif file_size > 0:
            score += 8
            feedback_parts.append("File exists but format invalid (8/15)")
            subscores['file_valid'] = False
        else:
            feedback_parts.append("File empty or invalid (0/15)")
            subscores['file_valid'] = False
    except Exception as e:
        logger.warning(f"Criterion 1 check failed: {e}")

    # Criterion 2: Page count == 4 (15 pts)
    try:
        page_count = int(result.get('page_count', 0))
        if page_count >= 4:
            score += 15
            feedback_parts.append(f"Correct page count: {page_count} pages (15/15)")
            subscores['pages'] = True
        elif page_count == 3:
            score += 8
            feedback_parts.append(f"Only 3 pages, expected 4 (8/15)")
            subscores['pages'] = False
        elif page_count == 2:
            score += 4
            feedback_parts.append(f"Only 2 pages, expected 4 (4/15)")
            subscores['pages'] = False
        else:
            feedback_parts.append(f"Insufficient pages: {page_count} (0/15)")
            subscores['pages'] = False
    except Exception as e:
        logger.warning(f"Criterion 2 check failed: {e}")

    # Criterion 3: "Charlotte" text present (15 pts)
    try:
        if result.get('has_charlotte', False):
            score += 15
            feedback_parts.append("'Charlotte' present (book title / character) (15/15)")
            subscores['charlotte'] = True
        else:
            feedback_parts.append("Missing 'Charlotte' text (0/15)")
            subscores['charlotte'] = False
    except Exception as e:
        logger.warning(f"Criterion 3 check failed: {e}")

    # Criterion 4: "Wilbur" text present (15 pts)
    try:
        if result.get('has_wilbur', False):
            score += 15
            feedback_parts.append("'Wilbur' character present (15/15)")
            subscores['wilbur'] = True
        else:
            feedback_parts.append("Missing 'Wilbur' character text (0/15)")
            subscores['wilbur'] = False
    except Exception as e:
        logger.warning(f"Criterion 4 check failed: {e}")

    # Criterion 5: "Fern" text present (10 pts)
    try:
        if result.get('has_fern', False):
            score += 10
            feedback_parts.append("'Fern' character present (10/10)")
            subscores['fern'] = True
        else:
            feedback_parts.append("Missing 'Fern' character text (0/10)")
            subscores['fern'] = False
    except Exception as e:
        logger.warning(f"Criterion 5 check failed: {e}")

    # Criterion 6: "Comprehension" / "Questions" (10 pts)
    try:
        if result.get('has_comprehension', False):
            score += 10
            feedback_parts.append("Comprehension questions section present (10/10)")
            subscores['comprehension'] = True
        else:
            feedback_parts.append("Missing comprehension questions section (0/10)")
            subscores['comprehension'] = False
    except Exception as e:
        logger.warning(f"Criterion 6 check failed: {e}")

    # Criterion 7: Rectangle shapes >= 3 (character boxes) (15 pts)
    try:
        rect_count = int(result.get('rect_count', 0))
        total_shapes = int(result.get('total_shape_count', 0))
        effective_rects = rect_count if rect_count > 0 else total_shapes
        if rect_count >= 3:
            score += 15
            feedback_parts.append(f"Character analysis boxes (rectangles): {rect_count} (15/15)")
            subscores['char_boxes'] = True
        elif effective_rects >= 2:
            score += 8
            feedback_parts.append(f"Only {rect_count} rectangles, expected 3+ (8/15)")
            subscores['char_boxes'] = False
        else:
            feedback_parts.append(f"Insufficient character boxes: {rect_count} rectangles (0/15)")
            subscores['char_boxes'] = False
    except Exception as e:
        logger.warning(f"Criterion 7 check failed: {e}")

    # Criterion 8: Theme/Message page (5 pts)
    try:
        if result.get('has_theme', False):
            score += 5
            feedback_parts.append("Theme and message page present (5/5)")
            subscores['theme'] = True
        else:
            feedback_parts.append("Missing theme/message page (0/5)")
            subscores['theme'] = False
    except Exception as e:
        logger.warning(f"Criterion 8 check failed: {e}")

    passed = score >= 70
    feedback = " | ".join(feedback_parts) if feedback_parts else "No criteria met"

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "subscores": subscores,
        "details": {
            "page_count": result.get('page_count', 0),
            "file_valid": result.get('file_valid', False),
            "created_during_task": result.get('created_during_task', False),
            "rect_count": result.get('rect_count', 0),
        }
    }
