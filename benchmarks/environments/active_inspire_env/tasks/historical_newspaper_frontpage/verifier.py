#!/usr/bin/env python3
"""
Verifier for historical_newspaper_frontpage task.

Scoring System (100 points total, Pass >= 70):
1. File Validation (15 pts): File exists, is valid zip/xml, created during task.
2. Page Count (10 pts): Exactly 2 pages.
3. Content - Page 1 (Front Page) (50 pts total):
   - Masthead "Independence Gazette" (10 pts)
   - Dateline "Philadelphia" + "1776" (10 pts)
   - Headline "Independence Declared" (10 pts)
   - Byline "Benjamin Harris" (5 pts)
   - Body text "Continental Congress" or "Declaration..." (10 pts)
   - Sidebar "King George" (5 pts)
4. Content - Page 2 (Instructions) (10 pts):
   - Title "Assignment" present (5 pts)
   - At least 1 rectangle shape (instruction box) (5 pts)
5. Layout/Shapes (15 pts):
   - At least 2 lines or rectangles on Page 1 (for column dividers) (10 pts)
   - Valid timestamp check (5 pts)
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_historical_newspaper(traj, env_info, task_info):
    """
    Verify the historical newspaper flipchart task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No copy_from_env function available"
        }

    # Load result from container
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
    
    # --- 1. File Validation (15 pts) ---
    if result.get('file_found') and result.get('file_valid') and result.get('file_size', 0) > 1000:
        score += 15
        feedback_parts.append("Valid flipchart file created (15/15)")
    else:
        feedback_parts.append("File missing or invalid (0/15)")
        # Critical failure if no file
        if not result.get('file_found'):
            return {"passed": False, "score": 0, "feedback": "File not found"}

    # --- 2. Page Count (10 pts) ---
    page_count = result.get('page_count', 0)
    if page_count == 2:
        score += 10
        feedback_parts.append("Page count correct: 2 (10/10)")
    else:
        feedback_parts.append(f"Incorrect page count: {page_count} (expected 2) (0/10)")

    # --- 3. Content - Page 1 (50 pts) ---
    p1_score = 0
    if result.get('has_masthead'): p1_score += 10
    if result.get('has_dateline'): p1_score += 10
    if result.get('has_headline'): p1_score += 10
    if result.get('has_byline'): p1_score += 5
    if result.get('has_body'): p1_score += 10
    if result.get('has_sidebar'): p1_score += 5
    
    score += p1_score
    feedback_parts.append(f"Front Page content: {p1_score}/50 pts")
    
    if p1_score < 30:
        missing = []
        if not result.get('has_masthead'): missing.append("Masthead")
        if not result.get('has_headline'): missing.append("Headline")
        if not result.get('has_body'): missing.append("Body text")
        feedback_parts.append(f"Missing P1 content: {', '.join(missing)}")

    # --- 4. Content - Page 2 (10 pts) ---
    p2_score = 0
    if result.get('has_assignment'): p2_score += 5
    
    # Check for box on page 2 (using total rect count as proxy if specific page parsing unavailable in shell script)
    # The shell script sums counts. We require at least 1 rectangle overall for the box.
    # Note: Layout section below checks for dividers.
    if result.get('rect_count', 0) >= 1: 
        p2_score += 5
    
    score += p2_score
    feedback_parts.append(f"Assignment Page content: {p2_score}/10 pts")

    # --- 5. Layout & Timestamp (15 pts) ---
    layout_score = 0
    
    # Column dividers: need lines or rects.
    # We want at least 2 dividers (Page 1) + 1 box (Page 2) = 3 total shapes minimum ideally.
    # Shell script provides 'line_count' and 'rect_count'.
    total_shapes = result.get('line_count', 0) + result.get('rect_count', 0) + result.get('total_shape_count', 0)
    
    if total_shapes >= 3:
        layout_score += 10
        feedback_parts.append("Layout elements (dividers/boxes) found (10/10)")
    elif total_shapes >= 1:
        layout_score += 5
        feedback_parts.append("Some layout elements found (5/10)")
    else:
        feedback_parts.append("No layout shapes found (0/10)")
        
    if result.get('created_during_task'):
        layout_score += 5
        feedback_parts.append("Timestamp valid (5/5)")
    else:
        feedback_parts.append("File created before task start? (0/5)")
        
    score += layout_score

    # Final result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }