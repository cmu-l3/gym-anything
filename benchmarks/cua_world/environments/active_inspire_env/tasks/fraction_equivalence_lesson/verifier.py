#!/usr/bin/env python3
"""
Verifier for fraction_equivalence_lesson task.

Scoring Breakdown (100 points total):
1. File Existence & Validity (15 pts)
2. Page Count == 2 (10 pts)
3. Vocabulary Terms (Numerator/Denominator) (15 pts)
4. Fraction Labels (10 pts for 1/2s, 10 pts for 1/4s, 15 pts for 1/8s)
5. Visual Structure (Rectangle Count >= 15) (15 pts)
6. Formatting (Color Diversity) (10 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fraction_lesson(traj, env_info, task_info):
    """
    Verify the fraction lesson flipchart creation.
    """
    # 1. Setup - Get Result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function missing"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()
        copy_from_env('/tmp/task_result.json', tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Export failed or file missing: {e}"}

    # 2. Evaluation Logic
    score = 0
    feedback_parts = []
    
    # Criterion 1: File Existence (15 pts)
    if result.get('file_found') and result.get('file_valid') and result.get('created_during_task'):
        score += 15
        feedback_parts.append("Valid flipchart created (15/15)")
    elif result.get('file_found'):
        score += 5
        feedback_parts.append("File found but invalid/old (5/15)")
    else:
        return {"passed": False, "score": 0, "feedback": "No output file found"}

    # Criterion 2: Page Count (10 pts)
    pg_count = result.get('page_count', 0)
    if pg_count == 2:
        score += 10
        feedback_parts.append("Correct page count (10/10)")
    elif pg_count >= 1:
        score += 5
        feedback_parts.append(f"Incorrect page count: {pg_count} (5/10)")
    else:
        feedback_parts.append("No pages found (0/10)")

    # Criterion 3: Vocabulary (15 pts)
    vocab_score = 0
    if result.get('has_numerator'): vocab_score += 7.5
    if result.get('has_denominator'): vocab_score += 7.5
    score += int(vocab_score)
    if vocab_score == 15:
        feedback_parts.append("Vocabulary complete (15/15)")
    else:
        feedback_parts.append(f"Vocabulary partial ({vocab_score}/15)")

    # Criterion 4: Fraction Labels (35 pts total)
    # Expect: >=2 '1/2', >=4 '1/4', >=8 '1/8'
    label_score = 0
    
    c_half = result.get('count_1_2', 0)
    if c_half >= 2: label_score += 10
    elif c_half > 0: label_score += 5
    
    c_quarter = result.get('count_1_4', 0)
    if c_quarter >= 4: label_score += 10
    elif c_quarter > 0: label_score += 5
    
    c_eighth = result.get('count_1_8', 0)
    if c_eighth >= 8: label_score += 15
    elif c_eighth > 0: label_score += 5
    
    score += label_score
    feedback_parts.append(f"Labels score: {label_score}/35")

    # Criterion 5: Shape Count (15 pts)
    # Wall needs 1+2+4+8 = 15 rectangles minimum
    rect_count = result.get('rectangle_count', 0)
    if rect_count >= 15:
        score += 15
        feedback_parts.append(f"Visual structure good ({rect_count} rectangles) (15/15)")
    elif rect_count >= 5:
        score += 5
        feedback_parts.append(f"Incomplete structure ({rect_count} rectangles) (5/15)")
    else:
        feedback_parts.append("Visual structure missing (0/15)")

    # Criterion 6: Color Diversity (10 pts)
    # We expect at least 3 distinct fill colors for rows
    colors = result.get('color_diversity_count', 0)
    if colors >= 3:
        score += 10
        feedback_parts.append("Good color usage (10/10)")
    elif colors >= 2:
        score += 5
        feedback_parts.append("Low color diversity (5/10)")
    else:
        feedback_parts.append("Monochrome/Default colors (0/10)")

    # Final Result
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }