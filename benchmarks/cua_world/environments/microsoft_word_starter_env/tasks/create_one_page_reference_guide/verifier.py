#!/usr/bin/env python3
"""
Verifier for create_one_page_reference_guide task.

Metric Logic:
1. File Existence (10pts)
2. Page Layout (Landscape) (20pts)
3. Columns (3 columns) (20pts)
4. Fit to Page (Exactly 1 page) (30pts)
5. Content Integrity (Text not deleted) (20pts)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_one_page_reference_guide(traj, env_info, task_info):
    """
    Verifies the Word document layout properties exported by the PowerShell script.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Output File Exists
    if result.get('output_exists', False):
        score += 10
        feedback_parts.append("File 'reference_guide.docx' saved")
    else:
        return {"passed": False, "score": 0, "feedback": "File 'reference_guide.docx' not found"}

    # 2. Landscape Orientation
    if result.get('is_landscape', False):
        score += 20
        feedback_parts.append("Orientation: Landscape (Pass)")
    else:
        feedback_parts.append("Orientation: Portrait (Fail - must be Landscape)")

    # 3. Columns (Target: 3)
    cols = result.get('column_count', 0)
    if cols == 3:
        score += 20
        feedback_parts.append("Columns: 3 (Pass)")
    elif cols >= 2:
        score += 10
        feedback_parts.append(f"Columns: {cols} (Partial - target is 3)")
    else:
        feedback_parts.append(f"Columns: {cols} (Fail - target is 3)")

    # 4. Content Integrity (Min 55 paragraphs)
    # The source has ~62 paragraphs. Agent should not delete many.
    paras = result.get('paragraph_count', 0)
    if paras >= 55:
        score += 20
        feedback_parts.append(f"Content: {paras} items (Pass)")
    else:
        # If score is low, they might have deleted text to make it fit
        score += 0
        feedback_parts.append(f"Content: {paras} items (Fail - too much text deleted)")

    # 5. Fit to Page (Target: 1 page)
    pages = result.get('page_count', 0)
    if pages == 1:
        score += 30
        feedback_parts.append("Page Count: 1 (Pass)")
    elif pages == 2:
        score += 10
        feedback_parts.append("Page Count: 2 (Partial - must be 1)")
    else:
        feedback_parts.append(f"Page Count: {pages} (Fail - must be 1)")
        
    # Bonus/Penalty for Title Layout (if detectable)
    # title_spans = result.get('title_spans_columns', False)
    # We won't strictly penalize this programmatic check as it's heuristic, 
    # but could use it for tie-breaking or detailed feedback.

    passed = (score >= 70 and pages == 1)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }