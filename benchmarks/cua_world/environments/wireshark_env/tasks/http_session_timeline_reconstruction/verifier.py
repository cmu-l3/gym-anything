#!/usr/bin/env python3
"""
Verifier for http_session_timeline_reconstruction task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_http_session_timeline(traj, env_info, task_info):
    """
    Verifies the CSV output of the HTTP session timeline task.
    
    Criteria:
    1. File exists and created during task (10 pts)
    2. Header row is exactly correct (20 pts)
    3. Row count matches ground truth (20 pts)
    4. Content accuracy (based on row-by-row comparison) (50 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
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
    
    # 1. File Existence & Anti-gaming (10 pts)
    if result.get('file_exists', False):
        if result.get('file_created_during_task', False):
            score += 10
            feedback_parts.append("File created successfully")
        else:
            score += 5
            feedback_parts.append("File exists but timestamp indicates pre-task creation")
    else:
        return {"passed": False, "score": 0, "feedback": "Output CSV file not found"}

    # 2. Header Match (20 pts)
    if result.get('header_match', False):
        score += 20
        feedback_parts.append("Header row correct")
    else:
        actual = result.get('actual_header', 'None')
        expected = result.get('expected_header', '')
        feedback_parts.append(f"Header mismatch. Expected: {expected[:30]}... Got: {actual[:30]}...")

    # 3. Row Count Match (20 pts)
    expected_rows = result.get('expected_row_count', 0)
    actual_rows = result.get('actual_row_count', 0)
    
    if result.get('row_count_match', False):
        score += 20
        feedback_parts.append(f"Row count correct ({actual_rows})")
    else:
        # Partial credit for being close
        diff = abs(expected_rows - actual_rows)
        if expected_rows > 0 and diff <= 2:
            score += 10
            feedback_parts.append(f"Row count close ({actual_rows} vs {expected_rows})")
        else:
            feedback_parts.append(f"Row count mismatch: {actual_rows} vs {expected_rows}")

    # 4. Content Accuracy (50 pts)
    # Scaled by the match score calculated in export_result.sh
    match_pct = result.get('content_match_score', 0)
    content_points = int((match_pct / 100) * 50)
    score += content_points
    
    if match_pct == 100:
        feedback_parts.append("Content perfectly matches ground truth")
    elif match_pct >= 90:
        feedback_parts.append(f"Content matches {match_pct}% (High accuracy)")
    elif match_pct > 0:
        feedback_parts.append(f"Content matches {match_pct}% (Check field ordering/formatting)")
    else:
        feedback_parts.append("Content does not match ground truth")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }