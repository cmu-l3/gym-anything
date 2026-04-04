#!/usr/bin/env python3
"""
Verifier for spanish_vocab_flashcards task.

Verification Criteria (100 points total, Pass >= 70):
1. File Validation (15 pts): File exists, is valid flipchart format.
2. Page Count (10 pts): Exactly 4 pages.
3. Timestamp (5 pts): Created during task.
4. Shapes (10 pts): At least 4 shapes detected (one for title page, 3 placeholders).
5. Text Content (60 pts):
   - "La Casa" (10 pts)
   - "Vocabulario" (5 pts)
   - "La cocina" (10 pts)
   - "Kitchen" (5 pts)
   - "El dormitorio" (10 pts)
   - "Bedroom" (5 pts)
   - "El baño" (10 pts)
   - "Bathroom" (5 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_spanish_vocab_flashcards(traj, env_info, task_info):
    """
    Verify the Spanish vocabulary flashcards task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No copy_from_env function available"
        }

    # Retrieve result JSON from container
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()
        try:
            copy_from_env('/tmp/task_result.json', tmp_path)
            with open(tmp_path, 'r', encoding='utf-8') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read task result file: {e}"
        }

    score = 0
    feedback_parts = []
    
    # 1. File Validation (15 pts)
    if result.get('file_found', False):
        if result.get('file_valid', False):
            score += 15
            feedback_parts.append("Valid flipchart file found (+15)")
        else:
            score += 5
            feedback_parts.append("File found but format invalid (+5)")
    else:
        feedback_parts.append("No output file found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Timestamp check (5 pts)
    if result.get('created_during_task', False):
        score += 5
        feedback_parts.append("File created during task (+5)")
    else:
        feedback_parts.append("File timestamp invalid (pre-existing?)")

    # 3. Page Count (10 pts)
    # Strict requirement: 4 pages
    page_count = result.get('page_count', 0)
    if page_count == 4:
        score += 10
        feedback_parts.append("Correct page count (4) (+10)")
    else:
        feedback_parts.append(f"Incorrect page count: {page_count} (expected 4)")

    # 4. Shape Count (10 pts)
    # Expecting at least 4 shapes (1 decorative on p1 + 3 placeholders)
    shape_count = result.get('shape_count', 0)
    if shape_count >= 4:
        score += 10
        feedback_parts.append(f"Shapes found ({shape_count}) (+10)")
    else:
        feedback_parts.append(f"Not enough shapes found: {shape_count} (expected >= 4)")

    # 5. Text Content (60 pts total)
    text_content = result.get('text_content', {})
    
    # Page 1
    if text_content.get('has_title_casa', False):
        score += 10
        feedback_parts.append("'La Casa' found (+10)")
    else:
        feedback_parts.append("'La Casa' missing")

    if text_content.get('has_subtitle_vocab', False):
        score += 5
        feedback_parts.append("'Vocabulario' found (+5)")
    else:
        feedback_parts.append("'Vocabulario' missing")

    # Page 2
    if text_content.get('has_cocina', False):
        score += 10
        feedback_parts.append("'cocina' found (+10)")
    else:
        feedback_parts.append("'cocina' missing")

    if text_content.get('has_kitchen', False):
        score += 5
        feedback_parts.append("'Kitchen' found (+5)")
    else:
        feedback_parts.append("'Kitchen' missing")

    # Page 3
    if text_content.get('has_dormitorio', False):
        score += 10
        feedback_parts.append("'dormitorio' found (+10)")
    else:
        feedback_parts.append("'dormitorio' missing")

    if text_content.get('has_bedroom', False):
        score += 5
        feedback_parts.append("'Bedroom' found (+5)")
    else:
        feedback_parts.append("'Bedroom' missing")

    # Page 4
    if text_content.get('has_bano', False):
        score += 10
        feedback_parts.append("'baño' found (+10)")
    else:
        feedback_parts.append("'baño' missing")

    if text_content.get('has_bathroom', False):
        score += 5
        feedback_parts.append("'Bathroom' found (+5)")
    else:
        feedback_parts.append("'Bathroom' missing")

    # Final result calculation
    # Pass threshold 70
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }