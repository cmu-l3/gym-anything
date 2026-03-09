#!/usr/bin/env python3
"""
Verifier for Growth Mindset SEL Lesson task.

Scoring (100 points, pass at 70):
  1. File exists + valid format (15 pts)
  2. Page count == 4 (10 pts)
  3. "Growth Mindset" title present (10 pts)
  4. "Fixed Mindset" title present (10 pts)
  5. Fixed phrases (2+ found) (10 pts)
  6. Growth phrases (2+ found) (10 pts)
  7. "Power of Yet" title present (10 pts)
  8. Goal page content present (10 pts)
  9. Total shapes >= 5 (10 pts)
  10. Star shape present (5 pts)
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_growth_mindset_lesson(traj, env_info, task_info):
    """
    Verify the Growth Mindset SEL flipchart creation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No copy_from_env function available"
        }

    # Read result
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
    
    # Check if file found
    if not result.get('file_found'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target file not found: growth_mindset_lesson.flipchart was not created"
        }

    # 1. File Validity (15 pts)
    if result.get('file_valid', False):
        score += 15
        feedback_parts.append("Valid flipchart created (15/15)")
    else:
        feedback_parts.append("File created but invalid format (0/15)")

    # 2. Page Count (10 pts)
    page_count = result.get('page_count', 0)
    if page_count == 4:
        score += 10
        feedback_parts.append("Correct page count: 4 (10/10)")
    elif page_count >= 3:
        score += 5
        feedback_parts.append(f"Page count {page_count} close to expected 4 (5/10)")
    else:
        feedback_parts.append(f"Incorrect page count: {page_count} (0/10)")

    # 3. Main Title (10 pts)
    if result.get('has_title', False):
        score += 10
        feedback_parts.append("Main title present (10/10)")
    else:
        feedback_parts.append("Missing 'Growth Mindset' title (0/10)")

    # 4. Fixed Mindset Title (10 pts)
    if result.get('has_fixed_title', False):
        score += 10
        feedback_parts.append("Comparison title present (10/10)")
    else:
        feedback_parts.append("Missing 'Fixed Mindset' text (0/10)")

    # 5. Fixed Phrases (10 pts)
    fixed_count = result.get('fixed_phrases_count', 0)
    if fixed_count >= 2:
        score += 10
        feedback_parts.append(f"Fixed mindset phrases found: {fixed_count} (10/10)")
    else:
        feedback_parts.append(f"Missing sufficient fixed phrases (found {fixed_count}) (0/10)")

    # 6. Growth Phrases (10 pts)
    growth_count = result.get('growth_phrases_count', 0)
    if growth_count >= 2:
        score += 10
        feedback_parts.append(f"Growth mindset phrases found: {growth_count} (10/10)")
    else:
        feedback_parts.append(f"Missing sufficient growth phrases (found {growth_count}) (0/10)")

    # 7. Power of Yet (10 pts)
    if result.get('has_yet_title', False):
        score += 10
        feedback_parts.append("'Power of Yet' title present (10/10)")
    else:
        feedback_parts.append("Missing 'Power of Yet' (0/10)")

    # 8. Goal Page (10 pts)
    if result.get('has_goal_title', False) or result.get('has_goal_prompt', False):
        score += 10
        feedback_parts.append("Goal page content present (10/10)")
    else:
        feedback_parts.append("Missing Goal page content (0/10)")

    # 9. Total Shapes (10 pts)
    total_shapes = result.get('total_shape_count', 0)
    if total_shapes >= 5:
        score += 10
        feedback_parts.append(f"Sufficient shapes used: {total_shapes} (10/10)")
    elif total_shapes >= 3:
        score += 5
        feedback_parts.append(f"Some shapes used: {total_shapes} (5/10)")
    else:
        feedback_parts.append(f"Too few shapes: {total_shapes} (0/10)")

    # 10. Star Shape (5 pts)
    if result.get('star_count', 0) > 0:
        score += 5
        feedback_parts.append("Star shape found (5/5)")
    else:
        feedback_parts.append("Missing star shape (0/5)")

    # Anti-gaming check: File created during task
    if not result.get('created_during_task', False):
        score = 0
        feedback_parts = ["FAILED: File timestamp indicates it was not created during this task session."]

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }