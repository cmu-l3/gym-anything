#!/usr/bin/env python3
"""
Verifier for classroom_schedule_flipchart task.

Scoring (100 points, pass at 70):
  Criterion 1: File exists + valid flipchart format        — 15 pts
  Criterion 2: Page count == 2                             — 10 pts
  Criterion 3: "Schedule"/"Agenda" text present            — 10 pts
  Criterion 4: Schedule activities (3+ of: Morning         — 20 pts
               Meeting, Reading, Math, Science, Lunch)
  Criterion 5: Rectangle shapes >= 8 (blocks + boxes)      — 20 pts
  Criterion 6: "Homework" text present                     — 15 pts
  Criterion 7: Subject homework items (2+ of: Math,        — 10 pts
               Reading, Science, Writing)
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_classroom_schedule_flipchart(traj, env_info, task_info):
    """
    Verify the classroom daily schedule display flipchart was correctly created.
    Checks 2 pages with schedule time blocks and homework subject boxes.
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
            "feedback": "Target file not found: daily_schedule.flipchart was not created"
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

    # Criterion 2: Page count == 2 (10 pts)
    try:
        page_count = int(result.get('page_count', 0))
        if page_count >= 2:
            score += 10
            feedback_parts.append(f"Correct page count: {page_count} pages (10/10)")
            subscores['pages'] = True
        elif page_count == 1:
            score += 4
            feedback_parts.append(f"Only 1 page, expected 2 (4/10)")
            subscores['pages'] = False
        else:
            feedback_parts.append(f"No pages detected (0/10)")
            subscores['pages'] = False
    except Exception as e:
        logger.warning(f"Criterion 2 check failed: {e}")

    # Criterion 3: Schedule/Agenda title (10 pts)
    try:
        if result.get('has_schedule', False):
            score += 10
            feedback_parts.append("'Daily Schedule' title present (10/10)")
            subscores['title'] = True
        else:
            feedback_parts.append("Missing 'Schedule'/'Agenda' title (0/10)")
            subscores['title'] = False
    except Exception as e:
        logger.warning(f"Criterion 3 check failed: {e}")

    # Criterion 4: Schedule activities present (20 pts)
    try:
        activities_found = []
        if result.get('has_morning_meeting', False):
            activities_found.append('Morning Meeting')
        if result.get('has_reading', False):
            activities_found.append('Reading')
        if result.get('has_math', False):
            activities_found.append('Math')
        if result.get('has_science', False):
            activities_found.append('Science')
        if result.get('has_lunch', False):
            activities_found.append('Lunch')

        num_activities = len(activities_found)
        if num_activities >= 4:
            score += 20
            feedback_parts.append(f"Schedule activities: {', '.join(activities_found)} (20/20)")
            subscores['activities'] = True
        elif num_activities == 3:
            score += 14
            feedback_parts.append(f"3/5 activities found: {', '.join(activities_found)} (14/20)")
            subscores['activities'] = False
        elif num_activities == 2:
            score += 8
            feedback_parts.append(f"2/5 activities found: {', '.join(activities_found)} (8/20)")
            subscores['activities'] = False
        elif num_activities == 1:
            score += 4
            feedback_parts.append(f"Only 1 activity found: {', '.join(activities_found)} (4/20)")
            subscores['activities'] = False
        else:
            feedback_parts.append("No schedule activities found (0/20)")
            subscores['activities'] = False
    except Exception as e:
        logger.warning(f"Criterion 4 check failed: {e}")

    # Criterion 5: Rectangle shapes >= 8 (20 pts)
    try:
        rect_count = int(result.get('rect_count', 0))
        total_shapes = int(result.get('total_shape_count', 0))
        effective_rects = rect_count if rect_count > 0 else total_shapes
        if rect_count >= 8:
            score += 20
            feedback_parts.append(f"Schedule and homework blocks: {rect_count} rectangles (20/20)")
            subscores['shapes'] = True
        elif rect_count >= 5:
            score += 12
            feedback_parts.append(f"{rect_count} rectangles found, expected 8+ (12/20)")
            subscores['shapes'] = False
        elif rect_count >= 3:
            score += 6
            feedback_parts.append(f"Only {rect_count} rectangles found (6/20)")
            subscores['shapes'] = False
        else:
            feedback_parts.append(f"Insufficient rectangle blocks: {rect_count} (0/20)")
            subscores['shapes'] = False
    except Exception as e:
        logger.warning(f"Criterion 5 check failed: {e}")

    # Criterion 6: Homework page (15 pts)
    try:
        if result.get('has_homework', False):
            score += 15
            feedback_parts.append("Homework page present (15/15)")
            subscores['homework'] = True
        else:
            feedback_parts.append("Missing homework page (0/15)")
            subscores['homework'] = False
    except Exception as e:
        logger.warning(f"Criterion 6 check failed: {e}")

    # Criterion 7: Subject homework items (10 pts)
    try:
        subjects_found = []
        if result.get('has_math', False):
            subjects_found.append('Math')
        if result.get('has_reading', False):
            subjects_found.append('Reading')
        if result.get('has_science', False):
            subjects_found.append('Science')

        if len(subjects_found) >= 2:
            score += 10
            feedback_parts.append(f"Homework subjects: {', '.join(subjects_found)} (10/10)")
            subscores['hw_subjects'] = True
        elif len(subjects_found) == 1:
            score += 5
            feedback_parts.append(f"Only 1 homework subject: {subjects_found[0]} (5/10)")
            subscores['hw_subjects'] = False
        else:
            feedback_parts.append("No homework subject labels found (0/10)")
            subscores['hw_subjects'] = False
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
            "rect_count": result.get('rect_count', 0),
        }
    }
