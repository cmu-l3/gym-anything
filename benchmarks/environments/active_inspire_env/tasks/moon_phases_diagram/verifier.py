#!/usr/bin/env python3
"""
Verifier for moon_phases_diagram task.

Scoring System (100 points total, 70 to pass):
- File existence & validity: 15 pts
- Page count (exactly 4): 10 pts
- Page 1 Content (Title "Moon Phases"): 5 pts
- Page 1 Content (Duration "29.5"/"29"): 5 pts
- Page 2 Phases (names present): 20 pts (scaled based on count, >=6 required for partial)
- Page 2 Phases (all 8 bonus): 10 pts
- Page 2 Diagram (Shapes >= 8): 15 pts
- Page 3 Explanation (Sun & Earth): 10 pts
- Page 4 Activity (Title & "order"/"sequence"): 10 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_moon_phases_diagram(traj, env_info, task_info):
    """
    Verify the Moon Phases flipchart creation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No copy_from_env function available"
        }

    # Retrieve result from container
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
    
    # 1. File Existence & Validity (15 pts)
    # This is a gatekeeper. If file doesn't exist or isn't valid, score is low.
    file_found = result.get('file_found', False)
    file_valid = result.get('file_valid', False)
    created_during = result.get('created_during_task', False)
    
    if file_found and file_valid and created_during:
        score += 15
        feedback_parts.append("Valid flipchart file created (15/15)")
    elif file_found and file_valid:
        # File exists but timestamp issue (maybe pre-existing?)
        score += 5
        feedback_parts.append("File exists but timestamp verification failed (5/15)")
    elif file_found:
        score += 5
        feedback_parts.append("File created but invalid format (5/15)")
    else:
        feedback_parts.append("No output file found (0/15)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Page Count (10 pts)
    page_count = result.get('page_count', 0)
    if page_count == 4:
        score += 10
        feedback_parts.append("Correct page count: 4 (10/10)")
    else:
        feedback_parts.append(f"Incorrect page count: {page_count}, expected 4 (0/10)")

    # 3. Page 1 Content (10 pts)
    if result.get('has_title', False):
        score += 5
        feedback_parts.append("Title 'Moon Phases' found (5/5)")
    else:
        feedback_parts.append("Title missing (0/5)")
        
    if result.get('has_duration', False):
        score += 5
        feedback_parts.append("Duration (29.5/29 days) found (5/5)")
    else:
        feedback_parts.append("Duration text missing (0/5)")

    # 4. Page 2 Phases (30 pts max)
    # - 20 pts for getting at least 6/8
    # - 10 bonus pts for getting all 8
    phase_count = result.get('phase_count', 0)
    
    if phase_count == 8:
        score += 30
        feedback_parts.append("All 8 Moon Phases identified (30/30)")
    elif phase_count >= 6:
        score += 20
        feedback_parts.append(f"Most Moon Phases identified ({phase_count}/8) (20/30)")
    elif phase_count > 0:
        partial = int((phase_count / 8.0) * 20)
        score += partial
        feedback_parts.append(f"Some Moon Phases identified ({phase_count}/8) ({partial}/30)")
    else:
        feedback_parts.append("No Moon Phase terms found (0/30)")

    # 5. Page 2 Diagram Shapes (15 pts)
    shape_count = result.get('shape_count', 0)
    if shape_count >= 8:
        score += 15
        feedback_parts.append(f"Diagram shapes detected ({shape_count}+) (15/15)")
    elif shape_count >= 4:
        score += 7
        feedback_parts.append(f"Partial shapes detected ({shape_count}) (7/15)")
    else:
        feedback_parts.append(f"Few or no shapes detected ({shape_count}) (0/15)")

    # 6. Page 3 Explanation (10 pts)
    if result.get('has_sun', False) and result.get('has_earth', False):
        score += 10
        feedback_parts.append("Explanation mentions Sun and Earth (10/10)")
    elif result.get('has_sun', False) or result.get('has_earth', False):
        score += 5
        feedback_parts.append("Explanation mentions Sun or Earth, but not both (5/10)")
    else:
        feedback_parts.append("Explanation missing key terms (0/10)")

    # 7. Page 4 Activity (10 pts)
    if result.get('has_activity', False) and result.get('has_order_term', False):
        score += 10
        feedback_parts.append("Activity page with ordering instruction found (10/10)")
    elif result.get('has_activity', False) or result.get('has_order_term', False):
        score += 5
        feedback_parts.append("Partial Activity page content found (5/10)")
    else:
        feedback_parts.append("Activity page content missing (0/10)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }