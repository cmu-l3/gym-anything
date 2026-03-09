#!/usr/bin/env python3
"""
Verifier for simple_machines_diagrams task.

Scoring (100 points total, pass at 70):
1. File Validity (20 pts)
   - Exists, valid format, created during task
2. Page Structure (15 pts)
   - Exactly 3 pages
3. Content - Page 1 (10 pts)
   - "Simple Machines" title + list items
4. Content - Page 2 (25 pts)
   - Definition text (10)
   - Diagram shapes (Triangle + Beam) (10)
   - Labels (5)
5. Content - Page 3 (30 pts)
   - Definition text (10)
   - Diagram shapes (Triangle/Ramp) (15)
   - Labels (5)
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_simple_machines_diagrams(traj, env_info, task_info):
    """
    Verify the Simple Machines flipchart creation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No copy_from_env function available"
        }

    # Load result
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()
        try:
            copy_from_env('/tmp/task_result.json', tmp_path)
            with open(tmp_path, 'r') as f:
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
    
    # Check if file exists
    if not result.get('file_found', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target flipchart file not found."
        }

    # 1. File Validity (20 pts)
    if result.get('file_valid', False) and result.get('created_during_task', False):
        score += 20
        feedback_parts.append("Valid file created (20/20)")
    else:
        feedback_parts.append("File invalid or pre-existing (0/20)")

    # 2. Page Structure (15 pts)
    page_count = result.get('page_count', 0)
    if page_count == 3:
        score += 15
        feedback_parts.append("Page count 3 (15/15)")
    elif page_count > 0:
        score += 5
        feedback_parts.append(f"Page count {page_count} != 3 (5/15)")
    else:
        feedback_parts.append("Page count 0 (0/15)")

    # 3. Page 1 Content (10 pts)
    if result.get('has_title', False) and result.get('has_list_items', False):
        score += 10
        feedback_parts.append("Page 1 content correct (10/10)")
    elif result.get('has_title', False):
        score += 5
        feedback_parts.append("Page 1 title present, list missing (5/10)")
    else:
        feedback_parts.append("Page 1 content missing (0/10)")

    # 4. Page 2 Content (Lever) (25 pts)
    p2_score = 0
    if result.get('has_lever_def', False):
        p2_score += 10
    
    # Check diagrams via shape counts
    # Lever needs at least 1 triangle (fulcrum) and 1 rect/line (beam)
    triangles = result.get('triangle_count', 0)
    rect_lines = result.get('rect_line_count', 0)
    
    # We check global counts because XML parsing per page in bash is tricky without specialized tools.
    # Requirement: Total >= 2 triangles (Lever fulcrum + Ramp) and >= 1 beam
    if triangles >= 1 and rect_lines >= 1:
        p2_score += 10
    elif triangles >= 1:
        p2_score += 5
    
    if result.get('has_lever_labels', False):
        p2_score += 5
        
    score += p2_score
    feedback_parts.append(f"Lever page score ({p2_score}/25)")

    # 5. Page 3 Content (Inclined Plane) (30 pts)
    p3_score = 0
    if result.get('has_ramp_def', False):
        p3_score += 10
        
    # Ramp needs a triangle
    if triangles >= 2: # At least 2 total (1 for lever, 1 for ramp)
        p3_score += 15
    elif triangles >= 1: # Only 1 found total
        # Hard to say which one it is, give partial credit if we didn't give full credit in P2
        # But here we just assume if there's only 1 triangle total, one diagram is missing.
        p3_score += 5
        
    if result.get('has_ramp_label', False):
        p3_score += 5
        
    score += p3_score
    feedback_parts.append(f"Inclined Plane page score ({p3_score}/30)")

    # Final check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }