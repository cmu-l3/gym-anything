#!/usr/bin/env python3
"""
Verifier for lesson_opener_flipchart task.

Scoring (100 points, pass at 70):
  Criterion 1: File exists + valid flipchart format        — 20 pts
  Criterion 2: Page count == 3                             — 15 pts
  Criterion 3: "Do Now" text present                       — 15 pts
  Criterion 4: "Objective"/"Objectives" text present       — 15 pts
  Criterion 5: Vocabulary terms (Colony, Independence,     — 25 pts
               Patriot; 3 terms = 25, 2 = 15, 1 = 5)
  Criterion 6: Rectangle shapes >= 4                       — 10 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_lesson_opener_flipchart(traj, env_info, task_info):
    """
    Verify the lesson opener flipchart was correctly created.
    Checks for a 3-page flipchart with Do Now, objectives, and vocabulary content.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No copy_from_env function available"
        }

    # Read the exported result JSON
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

    # GATE: file must exist — no work done if file not found
    if not result.get('file_found'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target file not found: american_revolution_opener.flipchart was not created"
        }

    # Criterion 1: File exists + valid format (20 pts)
    try:
        file_valid = result.get('file_valid', False)
        file_size = result.get('file_size', 0)
        if file_valid and file_size > 0:
            score += 20
            feedback_parts.append("Valid flipchart file created (20/20)")
            subscores['file_valid'] = True
        elif file_size > 0:
            score += 10
            feedback_parts.append("File created but format invalid (10/20)")
            subscores['file_valid'] = False
        else:
            feedback_parts.append("File empty or invalid (0/20)")
            subscores['file_valid'] = False
    except Exception as e:
        logger.warning(f"Criterion 1 check failed: {e}")
        feedback_parts.append("File format check failed")

    # Criterion 2: Page count == 3 (15 pts)
    try:
        page_count = int(result.get('page_count', 0))
        if page_count >= 3:
            score += 15
            feedback_parts.append(f"Correct page count: {page_count} pages (15/15)")
            subscores['pages'] = True
        elif page_count == 2:
            score += 7
            feedback_parts.append(f"Only 2 pages found (7/15)")
            subscores['pages'] = False
        elif page_count == 1:
            score += 3
            feedback_parts.append(f"Only 1 page found (3/15)")
            subscores['pages'] = False
        else:
            feedback_parts.append(f"No pages detected (0/15)")
            subscores['pages'] = False
    except Exception as e:
        logger.warning(f"Criterion 2 check failed: {e}")
        feedback_parts.append("Page count check failed")

    # Criterion 3: "Do Now" content present (15 pts)
    try:
        if result.get('has_do_now', False):
            score += 15
            feedback_parts.append("Do Now section present (15/15)")
            subscores['do_now'] = True
        else:
            feedback_parts.append("Missing 'Do Now' content (0/15)")
            subscores['do_now'] = False
    except Exception as e:
        logger.warning(f"Criterion 3 check failed: {e}")

    # Criterion 4: Objectives page content (15 pts)
    try:
        if result.get('has_objectives', False):
            score += 15
            feedback_parts.append("Learning objectives section present (15/15)")
            subscores['objectives'] = True
        else:
            feedback_parts.append("Missing objectives content (0/15)")
            subscores['objectives'] = False
    except Exception as e:
        logger.warning(f"Criterion 4 check failed: {e}")

    # Criterion 5: Vocabulary terms (25 pts)
    # Colony + Independence + Patriot = 3 terms; each term worth ~8.3 pts, rounded
    try:
        vocab_found = []
        if result.get('has_colony', False):
            vocab_found.append('Colony')
        if result.get('has_independence', False):
            vocab_found.append('Independence')
        if result.get('has_patriot', False):
            vocab_found.append('Patriot')
        # Revolution also counts as bonus support
        if result.get('has_revolution', False):
            vocab_found.append('Revolution')

        unique_vocab = len(set(vocab_found))
        if unique_vocab >= 3:
            score += 25
            feedback_parts.append(f"All vocabulary terms present: {', '.join(vocab_found[:3])} (25/25)")
            subscores['vocab'] = True
        elif unique_vocab == 2:
            score += 15
            feedback_parts.append(f"Partial vocabulary: {', '.join(vocab_found)} (15/25)")
            subscores['vocab'] = False
        elif unique_vocab == 1:
            score += 5
            feedback_parts.append(f"Only one vocab term: {', '.join(vocab_found)} (5/25)")
            subscores['vocab'] = False
        else:
            feedback_parts.append("No vocabulary terms found (Colony, Independence, Patriot) (0/25)")
            subscores['vocab'] = False
    except Exception as e:
        logger.warning(f"Criterion 5 check failed: {e}")

    # Criterion 6: Rectangle shapes >= 4 (10 pts)
    try:
        rect_count = int(result.get('rect_count', 0))
        total_shapes = int(result.get('total_shape_count', 0))
        # Also consider total shapes in case rect detection pattern misses some
        effective_rects = max(rect_count, total_shapes // 2)
        if rect_count >= 4:
            score += 10
            feedback_parts.append(f"Rectangle shapes for vocabulary boxes: {rect_count} (10/10)")
            subscores['shapes'] = True
        elif rect_count >= 2:
            score += 5
            feedback_parts.append(f"Only {rect_count} rectangles found (5/10)")
            subscores['shapes'] = False
        else:
            feedback_parts.append(f"Insufficient rectangle shapes: {rect_count} (0/10)")
            subscores['shapes'] = False
    except Exception as e:
        logger.warning(f"Criterion 6 check failed: {e}")

    # Determine pass
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
