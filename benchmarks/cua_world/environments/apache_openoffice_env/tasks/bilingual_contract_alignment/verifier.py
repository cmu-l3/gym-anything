#!/usr/bin/env python3
"""
Verifier for bilingual_contract_alignment task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bilingual_contract(traj, env_info, task_info):
    """
    Verify the bilingual contract task.
    
    Criteria:
    1. File exists and valid ODT (10 pts)
    2. Table structure used (2+ columns) (30 pts)
    3. Row alignment (English/German side-by-side) (30 pts)
    4. Content completeness (15 pts)
    5. Header/Page numbers present (5 pts)
    6. Borders hidden (10 pts)
    """
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File Existence (10 pts)
    if not result.get("file_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file not found. Agent failed to save the document."
        }
    
    score += 10
    feedback_parts.append("File created")
    
    if not result.get("file_created_during_task", False):
        feedback_parts.append("(Warning: File timestamp looks old)")

    # 2. Table Structure (30 pts)
    has_table = result.get("has_table", False)
    # The regex in export might count total column definitions, but 2 is min for bilingual
    cols = result.get("table_columns", 0)
    
    if has_table:
        score += 20
        feedback_parts.append("Table structure detected")
        if cols >= 2:
            score += 10
            feedback_parts.append("Multi-column format confirmed")
        else:
            feedback_parts.append("Table found but column count unclear")
    else:
        feedback_parts.append("No table structure found (critical for side-by-side alignment)")

    # 3. Alignment (30 pts)
    # We use row_alignment_score from export (percentage of rows with >= 2 cells)
    alignment_score = result.get("row_alignment_score", 0.0)
    if alignment_score > 0.8:
        score += 30
        feedback_parts.append("Excellent row alignment")
    elif alignment_score > 0.5:
        score += 15
        feedback_parts.append("Partial row alignment detected")
    elif has_table:
        feedback_parts.append("Poor row alignment (cells may be merged or missing)")
    
    # 4. Content Completeness (15 pts)
    content_found = result.get("content_found", [])
    expected_phrases = 4 # From export script list
    found_count = len(content_found)
    
    content_points = int((found_count / expected_phrases) * 15)
    score += content_points
    if found_count == expected_phrases:
        feedback_parts.append("All key phrases found")
    else:
        feedback_parts.append(f"Content missing ({found_count}/{expected_phrases} phrases found)")

    # 5. Header/Footer (5 pts)
    if result.get("has_header", False):
        score += 3
        feedback_parts.append("Header present")
    if result.get("has_page_numbers", False):
        score += 2
        feedback_parts.append("Page numbers present")

    # 6. Hidden Borders (10 pts)
    if result.get("borders_hidden", False):
        score += 10
        feedback_parts.append("Table borders hidden (clean layout)")
    else:
        feedback_parts.append("Table borders visible (formatting not finalized)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }