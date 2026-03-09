#!/usr/bin/env python3
"""
Verifier for basketball_play_diagram task.

Criteria:
1. File Validity (20 pts): Exists, valid flipchart, created during task.
2. Page Count (20 pts): Exactly 3 pages.
3. Court Layout (15 pts): "Half Court" title + shapes (Rect/Circle).
4. Positions (25 pts): 5 positions found (PG, SG, SF, PF, C).
5. Play Diagram (20 pts): "Pick and Roll" + "Screen" + movement line.

Pass Threshold: 70 points.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_basketball_playbook(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No copy_from_env function available"
        }

    # Load result JSON
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
            "feedback": f"Could not read result file: {e}"
        }

    score = 0
    feedback_parts = []

    # 1. File Validity (20 pts)
    if result.get('file_found') and result.get('file_valid') and result.get('created_during_task'):
        score += 20
        feedback_parts.append("Valid file created (20/20)")
    elif result.get('file_found'):
        score += 5
        feedback_parts.append("File found but invalid or pre-existing (5/20)")
    else:
        feedback_parts.append("File not found (0/20)")
        return {"passed": False, "score": 0, "feedback": "File not found"}

    # 2. Page Count (20 pts)
    pg_count = result.get('page_count', 0)
    if pg_count == 3:
        score += 20
        feedback_parts.append("Correct page count (20/20)")
    elif pg_count > 0:
        score += 10
        feedback_parts.append(f"Incorrect page count: {pg_count} (10/20)")
    else:
        feedback_parts.append("No pages found (0/20)")

    # 3. Court Layout (15 pts)
    # Needs "Half Court" title and at least some shapes (Rect + Circle preferred)
    has_title_court = result.get('has_title_court', False)
    rects = result.get('rect_count', 0)
    circles = result.get('circle_count', 0)
    
    court_score = 0
    if has_title_court:
        court_score += 5
    if rects > 0:
        court_score += 5
    if circles > 0:
        court_score += 5
    
    score += court_score
    feedback_parts.append(f"Court layout: {court_score}/15 (Title: {has_title_court}, Rects: {rects}, Circles: {circles})")

    # 4. Positions (25 pts)
    # 5 pts per position found
    pos_found = result.get('positions_found_count', 0)
    # Cap at 5 just in case
    if pos_found > 5: pos_found = 5
    pos_score = pos_found * 5
    score += pos_score
    feedback_parts.append(f"Positions found: {pos_found}/5 ({pos_score}/25)")

    # 5. Play Diagram (20 pts)
    # Needs "Pick and Roll" (5), "Screen" (5), Lines (10)
    play_score = 0
    if result.get('has_title_play'):
        play_score += 5
    if result.get('has_text_screen'):
        play_score += 5
    if result.get('line_count', 0) > 0:
        play_score += 10
    
    score += play_score
    feedback_parts.append(f"Play diagram: {play_score}/20")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }