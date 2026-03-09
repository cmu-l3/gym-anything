#!/usr/bin/env python3
"""
Verifier for math_review_game_board task.

Scoring Criteria (100 points total, Pass threshold: 70):
1. File Existence & Validity (15 pts)
2. Page Count == 4 (10 pts)
3. Text Content (45 pts total)
   - Title "Jeopardy" (5)
   - Categories "Fractions", "Decimals", "Percentages" (15)
   - Point values "100", "200", "300" (at least 2 present) (10)
   - Question "3/4" (10)
   - Answer "1/4" or "5/4" (5)
4. Shapes/Grid Structure (30 pts)
   - At least 9 rectangles found (implies 3x3 grid) (15)
   - Created during task (Anti-gaming) (15)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_math_review_game_board(traj, env_info, task_info):
    """
    Verify the Math Jeopardy flipchart creation.
    """
    # 1. Setup: Retrieve result from container
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
            "feedback": f"Could not retrieve verification results: {e}"
        }

    score = 0
    feedback_parts = []

    # --- Criterion 1: File Existence & Validity (15 pts) ---
    if result.get('file_found') and result.get('file_valid'):
        score += 15
        feedback_parts.append("Valid flipchart file found (+15)")
    elif result.get('file_found'):
        score += 5
        feedback_parts.append("File found but invalid format (+5)")
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target flipchart file not found."
        }

    # --- Criterion 2: Page Count (10 pts) ---
    # Expect exactly 4 pages
    pg = result.get('page_count', 0)
    if pg == 4:
        score += 10
        feedback_parts.append("Page count is 4 (+10)")
    elif pg >= 3:
        score += 5
        feedback_parts.append(f"Page count is {pg}, expected 4 (+5)")
    else:
        feedback_parts.append(f"Page count {pg} insufficient")

    # --- Criterion 3: Text Content (45 pts) ---
    # Title
    if result.get('has_title'):
        score += 5
        feedback_parts.append("Title 'Jeopardy' found (+5)")
    
    # Categories (5 pts each)
    cats = 0
    if result.get('has_fractions'): cats += 1
    if result.get('has_decimals'): cats += 1
    if result.get('has_percentages'): cats += 1
    score += (cats * 5)
    if cats > 0:
        feedback_parts.append(f"{cats}/3 categories found (+{cats*5})")

    # Point Values (Need at least 2 of 100, 200, 300)
    points_found = 0
    if result.get('has_100'): points_found += 1
    if result.get('has_200'): points_found += 1
    if result.get('has_300'): points_found += 1
    
    if points_found >= 2:
        score += 10
        feedback_parts.append("Point values found (+10)")
    elif points_found == 1:
        score += 5
        feedback_parts.append("Some point values missing (+5)")

    # Question & Answer
    if result.get('has_question'):
        score += 10
        feedback_parts.append("Question content found (+10)")
    
    if result.get('has_answer'):
        score += 5
        feedback_parts.append("Answer content found (+5)")

    # --- Criterion 4: Shapes & Anti-Gaming (30 pts) ---
    # Grid requires 3x3 = 9 rectangles
    rects = result.get('rectangle_count', 0)
    if rects >= 9:
        score += 15
        feedback_parts.append("Game board grid (9+ rectangles) found (+15)")
    elif rects >= 4:
        score += 5
        feedback_parts.append(f"Partial grid ({rects} rectangles) (+5)")
    else:
        feedback_parts.append("Game board grid missing")

    # Anti-gaming: File modified during task
    if result.get('created_during_task'):
        score += 15
        feedback_parts.append("File created during task session (+15)")
    else:
        feedback_parts.append("Warning: File timestamp predates task!")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }