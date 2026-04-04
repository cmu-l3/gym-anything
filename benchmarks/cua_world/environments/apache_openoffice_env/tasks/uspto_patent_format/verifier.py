#!/usr/bin/env python3
"""
Verifier for uspto_patent_format task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_uspto_patent_format(traj, env_info, task_info):
    """
    Verify the formatting of the USPTO patent document.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Copy result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: File Existence and Validity (10 pts)
    if result.get("file_exists") and result.get("file_created_during_task"):
        score += 10
        feedback_parts.append("File created successfully")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found or not created during task"}

    # Criterion 2: Line Numbering (25 pts) - CRITICAL
    if result.get("line_numbering_enabled"):
        score += 25
        feedback_parts.append("Line numbering enabled")
    else:
        feedback_parts.append("Line numbering MISSING (Tools > Line Numbering)")

    # Criterion 3: Margins (15 pts)
    if result.get("margins_correct"):
        score += 15
        feedback_parts.append("Margins correct (1.0 inch)")
    else:
        feedback_parts.append("Margins incorrect (expected 1.0 inch)")

    # Criterion 4: Double Spacing (15 pts)
    if result.get("double_spacing_detected"):
        score += 15
        feedback_parts.append("Double spacing applied")
    else:
        feedback_parts.append("Double spacing MISSING")

    # Criterion 5: Claims List (15 pts)
    if result.get("claims_list_detected"):
        score += 15
        feedback_parts.append("Claims formatted as list")
    else:
        feedback_parts.append("Claims section not formatted as a list")

    # Criterion 6: Abstract Page Break (10 pts)
    if result.get("abstract_page_break"):
        score += 10
        feedback_parts.append("Abstract on new page")
    else:
        feedback_parts.append("Abstract NOT on new page")

    # Criterion 7: Font/Headings (10 pts)
    if result.get("font_size_12_detected") or result.get("headings_bold_caps"):
        score += 10
        feedback_parts.append("Font/Headings style updated")
    else:
        feedback_parts.append("Font/Headings style issues")

    # Final Score Calculation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }