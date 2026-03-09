#!/usr/bin/env python3
"""
Verifier for water_cycle_flipchart task.

Scoring (100 points, pass at 70):
  Criterion 1: File exists + valid flipchart format        — 20 pts
  Criterion 2: Page count == 3                             — 15 pts
  Criterion 3: "Water Cycle" title text present            — 10 pts
  Criterion 4: "Evaporation" text present                  — 15 pts
  Criterion 5: "Condensation" + "Precipitation" both       — 15 pts
               present (8 pts each)
  Criterion 6: Total shapes >= 3 (diagram elements)        — 15 pts
  Criterion 7: Assessment content on page 3 ("Quick        — 10 pts
               Check" or similar)
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_water_cycle_flipchart(traj, env_info, task_info):
    """
    Verify the water cycle science lesson flipchart was correctly created.
    Checks for 3 pages with water cycle stage terms and diagram shapes.
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
            "feedback": "Target file not found: water_cycle_lesson.flipchart was not created"
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
            feedback_parts.append("File exists but format invalid (10/20)")
            subscores['file_valid'] = False
        else:
            feedback_parts.append("File empty or invalid (0/20)")
            subscores['file_valid'] = False
    except Exception as e:
        logger.warning(f"Criterion 1 check failed: {e}")

    # Criterion 2: Page count == 3 (15 pts)
    try:
        page_count = int(result.get('page_count', 0))
        if page_count >= 3:
            score += 15
            feedback_parts.append(f"Correct page count: {page_count} pages (15/15)")
            subscores['pages'] = True
        elif page_count == 2:
            score += 7
            feedback_parts.append(f"Only 2 pages found, expected 3 (7/15)")
            subscores['pages'] = False
        else:
            feedback_parts.append(f"Insufficient pages: {page_count} (0/15)")
            subscores['pages'] = False
    except Exception as e:
        logger.warning(f"Criterion 2 check failed: {e}")

    # Criterion 3: Water Cycle title (10 pts)
    try:
        if result.get('has_water_cycle', False):
            score += 10
            feedback_parts.append("'Water Cycle' title present (10/10)")
            subscores['title'] = True
        else:
            feedback_parts.append("Missing 'Water Cycle' title (0/10)")
            subscores['title'] = False
    except Exception as e:
        logger.warning(f"Criterion 3 check failed: {e}")

    # Criterion 4: Evaporation text (15 pts)
    try:
        if result.get('has_evaporation', False):
            score += 15
            feedback_parts.append("'Evaporation' stage labeled (15/15)")
            subscores['evaporation'] = True
        else:
            feedback_parts.append("Missing 'Evaporation' text (0/15)")
            subscores['evaporation'] = False
    except Exception as e:
        logger.warning(f"Criterion 4 check failed: {e}")

    # Criterion 5: Condensation + Precipitation (15 pts: 7+8)
    try:
        has_cond = result.get('has_condensation', False)
        has_precip = result.get('has_precipitation', False)
        if has_cond and has_precip:
            score += 15
            feedback_parts.append("Both Condensation and Precipitation labeled (15/15)")
            subscores['stages'] = True
        elif has_cond or has_precip:
            score += 7
            missing = 'Precipitation' if has_cond else 'Condensation'
            feedback_parts.append(f"Missing '{missing}' stage (7/15)")
            subscores['stages'] = False
        else:
            feedback_parts.append("Missing both Condensation and Precipitation (0/15)")
            subscores['stages'] = False
    except Exception as e:
        logger.warning(f"Criterion 5 check failed: {e}")

    # Criterion 6: Shapes >= 3 (15 pts)
    try:
        rect_count = int(result.get('rect_count', 0))
        circle_count = int(result.get('circle_count', 0))
        total_shapes = int(result.get('total_shape_count', 0))
        # Count distinct shape types
        shape_total = rect_count + circle_count
        if shape_total == 0:
            shape_total = total_shapes
        if shape_total >= 3:
            score += 15
            feedback_parts.append(f"Diagram shapes present: {shape_total} shapes (15/15)")
            subscores['shapes'] = True
        elif shape_total >= 1:
            score += 7
            feedback_parts.append(f"Only {shape_total} shapes found, expected 3+ (7/15)")
            subscores['shapes'] = False
        else:
            feedback_parts.append("No diagram shapes found (0/15)")
            subscores['shapes'] = False
    except Exception as e:
        logger.warning(f"Criterion 6 check failed: {e}")

    # Criterion 7: Assessment/Quick Check content (10 pts)
    try:
        if result.get('has_quick_check', False):
            score += 10
            feedback_parts.append("Assessment/Quick Check page content present (10/10)")
            subscores['assessment'] = True
        else:
            feedback_parts.append("Missing Quick Check or assessment content (0/10)")
            subscores['assessment'] = False
    except Exception as e:
        logger.warning(f"Criterion 7 check failed: {e}")

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
            "total_shape_count": result.get('total_shape_count', 0),
        }
    }
