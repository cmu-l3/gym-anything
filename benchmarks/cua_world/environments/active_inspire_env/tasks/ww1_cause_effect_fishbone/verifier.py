#!/usr/bin/env python3
"""
Verifier for World War I Fishbone Diagram task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ww1_fishbone(traj, env_info, task_info):
    """
    Verify the WWI Fishbone diagram task.
    
    Scoring Criteria:
    1. File Creation (20 pts): Valid flipchart file created during task.
    2. Structure (20 pts): At least 5 lines (1 spine + 4 ribs) and 1 shape (head).
    3. Content (40 pts): 4 M.A.I.N. terms present (10 pts each).
    4. Labels (20 pts): Title and Head label present (10 pts each).
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment interface error"}

    # Retrieve result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. File Check (20 pts)
    if result.get("file_found", False) and result.get("file_valid", False):
        if result.get("created_during_task", False):
            score += 20
            feedback.append("Valid file created.")
        else:
            score += 10
            feedback.append("File exists but timestamp verification failed.")
    else:
        return {"passed": False, "score": 0, "feedback": "No valid flipchart file found."}

    # 2. Structure Check (20 pts)
    lines = result.get("line_count", 0)
    shapes = result.get("shape_count", 0)
    
    # Expecting at least 5 lines (1 spine + 4 ribs)
    if lines >= 5:
        score += 15
        feedback.append(f"Structure: {lines} lines found (min 5).")
    elif lines > 0:
        score += 5
        feedback.append(f"Structure: Only {lines} lines found (expected 5+).")
    else:
        feedback.append("Structure: No lines found.")

    # Expecting at least 1 shape for the head
    if shapes >= 1:
        score += 5
        feedback.append("Structure: Head shape found.")
    else:
        feedback.append("Structure: Head shape missing.")

    # 3. Content Check (40 pts - 10 per M.A.I.N term)
    main_terms = [
        ("Militarism", result.get("text_militarism", False)),
        ("Alliances", result.get("text_alliances", False)),
        ("Imperialism", result.get("text_imperialism", False)),
        ("Nationalism", result.get("text_nationalism", False))
    ]
    
    found_terms = 0
    for term, present in main_terms:
        if present:
            score += 10
            found_terms += 1
    
    if found_terms == 4:
        feedback.append("Content: All 4 M.A.I.N. causes found.")
    else:
        feedback.append(f"Content: Found {found_terms}/4 M.A.I.N. causes.")

    # 4. Labels Check (20 pts)
    if result.get("text_title", False):
        score += 10
        feedback.append("Label: Title found.")
    else:
        feedback.append("Label: Title 'Causes' missing.")
        
    if result.get("text_wwi", False):
        score += 10
        feedback.append("Label: 'WWI' label found.")
    else:
        feedback.append("Label: 'WWI' label missing.")

    # Final Verification
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }