#!/usr/bin/env python3
"""
Verifier for debate_organizer_flipchart task.

Scoring (100 points total):
1. File exists, valid format, created during task: 20 pts
2. Page count == 3: 10 pts
3. Page 1 Content (Title/Topic/Rules): 20 pts
4. Page 2 Content (Pro/Con/Args): 20 pts
5. Page 2 Structure (T-Chart lines): 10 pts
6. Page 3 Content (Sentence Starters): 20 pts

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_debate_organizer(traj, env_info, task_info):
    """
    Verify the debate organizer flipchart creation.
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
    
    # Check if file exists (Gatekeeper)
    if not result.get('file_found'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target file 'cell_phone_debate.flipchart' not found."
        }

    # 1. File Validity & Timestamp (20 pts)
    if result.get('file_valid') and result.get('created_during_task'):
        score += 20
        feedback_parts.append("Valid file created (20/20)")
    elif result.get('file_valid'):
        score += 10
        feedback_parts.append("File valid but timestamp check failed (10/20)")
    else:
        feedback_parts.append("File invalid or empty (0/20)")

    # 2. Page Count (10 pts)
    page_count = result.get('page_count', 0)
    if page_count == 3:
        score += 10
        feedback_parts.append("Correct page count (10/10)")
    elif page_count > 0:
        score += 5
        feedback_parts.append(f"Incorrect page count: {page_count} (5/10)")
    else:
        feedback_parts.append("No pages found (0/10)")

    # 3. Page 1 Content: Title, Topic, Rules (20 pts)
    p1_score = 0
    if result.get('has_title'): p1_score += 5
    if result.get('has_topic'): p1_score += 5
    if result.get('has_rules'): p1_score += 10
    score += p1_score
    if p1_score == 20:
        feedback_parts.append("Topic & Rules present (20/20)")
    else:
        feedback_parts.append(f"Missing some Page 1 content ({p1_score}/20)")

    # 4. Page 2 Content: Pro/Con/Args (20 pts)
    p2_score = 0
    if result.get('has_pro') and result.get('has_con'):
        p2_score += 10
    if result.get('has_args'):
        p2_score += 10
    score += p2_score
    if p2_score == 20:
        feedback_parts.append("Pro/Con content present (20/20)")
    else:
        feedback_parts.append(f"Missing Pro/Con labels or arguments ({p2_score}/20)")

    # 5. Page 2 Structure: T-Chart Lines (10 pts)
    if result.get('has_lines'):
        score += 10
        feedback_parts.append("T-Chart structure found (10/10)")
    else:
        feedback_parts.append("No T-Chart lines/shapes detected (0/10)")

    # 6. Page 3 Content: Sentence Starters (20 pts)
    if result.get('has_starters'):
        score += 20
        feedback_parts.append("Sentence starters present (20/20)")
    else:
        feedback_parts.append("Missing sentence starters (0/20)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }