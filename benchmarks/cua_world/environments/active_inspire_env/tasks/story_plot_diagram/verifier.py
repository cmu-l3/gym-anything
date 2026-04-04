#!/usr/bin/env python3
"""
Verifier for story_plot_diagram@1

This script verifies the creation of a 4-page ActivInspire flipchart
analyzing 'The Most Dangerous Game'.

Scoring Rubric (100 points total):
1. File Validity & Creation (15 pts)
2. Page Count Exactness (10 pts)
3. Title & Author on Page 1 (10 pts)
4. Diagram Structure - 5 Shapes (15 pts)
5. Plot Stage Labels - 5 Stages (20 pts)
6. Story Events - Character Names (15 pts)
7. Discussion Section (10 pts)
8. Anti-Gaming Timestamp Check (5 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_story_plot_diagram(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. File Validity (15 pts)
    if result.get("file_found", False) and result.get("file_size", 0) > 1000:
        score += 15
        feedback.append("Valid flipchart file found (+15)")
    else:
        feedback.append("File not found or empty (0)")
        return {"passed": False, "score": 0, "feedback": "Flipchart file not created"}

    # 2. Page Count (10 pts)
    # Exact match required for full points, slightly flexible if > 4
    pages = result.get("page_count", 0)
    if pages == 4:
        score += 10
        feedback.append("Exactly 4 pages created (+10)")
    elif pages > 4:
        score += 5
        feedback.append(f"Created {pages} pages (expected 4) (+5)")
    else:
        feedback.append(f"Insufficient pages: {pages} (expected 4) (0)")

    # 3. Title Content (10 pts)
    text = result.get("text_content", {})
    if text.get("has_title"):
        score += 5
        feedback.append("Story title found (+5)")
    if text.get("has_author"):
        score += 5
        feedback.append("Author name found (+5)")

    # 4. Diagram Structure (15 pts)
    shapes = result.get("shape_count", 0)
    if shapes >= 5:
        score += 15
        feedback.append(f"Diagram created with {shapes} shapes (+15)")
    elif shapes >= 3:
        score += 5
        feedback.append(f"Basic diagram detected ({shapes} shapes) (+5)")
    else:
        feedback.append(f"Diagram missing or too simple ({shapes} shapes) (0)")

    # 5. Plot Stage Labels (20 pts - 4 pts each)
    stages = ["has_exposition", "has_rising", "has_climax", "has_falling", "has_resolution"]
    found_stages = sum(1 for s in stages if text.get(s))
    score += (found_stages * 4)
    if found_stages > 0:
        feedback.append(f"Found {found_stages}/5 plot stage labels (+{found_stages * 4})")

    # 6. Story Events / Characters (15 pts)
    # Rainsford (8), Zaroff (7)
    if text.get("has_rainsford"):
        score += 8
        feedback.append("Character 'Rainsford' found (+8)")
    if text.get("has_zaroff"):
        score += 7
        feedback.append("Character 'Zaroff' found (+7)")

    # 7. Discussion Section (10 pts)
    if text.get("has_discussion"):
        score += 10
        feedback.append("Discussion section found (+10)")

    # 8. Anti-Gaming Timestamp (5 pts)
    if result.get("file_created_during_task", False):
        score += 5
        feedback.append("File verification: Created during task (+5)")
    else:
        feedback.append("File verification failed: Old file detected (0)")
        # Severe penalty if it looks like a pre-baked file, but we just withhold the 5 pts here
        # Ideally, we might fail the task, but the scoring rubric allows pass/fail based on total.

    passed = score >= 70
    final_feedback = f"Score: {score}/100. " + " | ".join(feedback)

    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback
    }