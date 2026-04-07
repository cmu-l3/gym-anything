#!/usr/bin/env python3
"""
Verifier for configure_gradebook_categories task.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_gradebook_config(traj, env_info, task_info):
    """
    Verify that the gradebook categories were configured correctly.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Metadata expectations
    metadata = task_info.get('metadata', {})
    expected_categories = metadata.get('expected_categories', [])
    
    # Extract actual categories found
    actual_categories = result.get('categories', [])
    course_period_id = result.get('course_period_id', 0)

    if course_period_id == 0:
        return {"passed": False, "score": 0, "feedback": "Target course section not found in database."}

    # Scoring
    score = 0
    feedback = []
    
    # 1. Check Total Count (25 pts)
    if len(actual_categories) == 3:
        score += 25
        feedback.append("Correct number of categories (3).")
    else:
        feedback.append(f"Incorrect number of categories: found {len(actual_categories)}, expected 3.")

    # 2. Check Each Expected Category (25 pts each)
    # Normalize data for comparison
    # We create a map of lowercase title -> weight
    actual_map = {}
    for cat in actual_categories:
        title = str(cat.get('title', '')).strip().lower()
        try:
            # Handle string weights "20.00" or int 20
            weight = float(cat.get('weight', 0))
        except:
            weight = 0.0
        actual_map[title] = weight

    for expected in expected_categories:
        exp_title = str(expected['title']).strip().lower()
        exp_weight = float(expected['weight'])
        
        if exp_title in actual_map:
            actual_weight = actual_map[exp_title]
            # Check weight with tolerance
            if abs(actual_weight - exp_weight) < 0.1:
                score += 25
                feedback.append(f"Category '{expected['title']}' correct ({actual_weight}%).")
            else:
                feedback.append(f"Category '{expected['title']}' found but weight incorrect (found {actual_weight}, expected {exp_weight}).")
        else:
            feedback.append(f"Category '{expected['title']}' missing.")

    # Anti-gaming check (Did they actually create data?)
    if len(actual_categories) > 0 and result.get('task_start', 0) > 0:
        # We assume if data exists it was created during task because we wiped it in setup
        pass
    elif len(actual_categories) == 0:
        # Already handled by scoring, but explicit note
        feedback.append("No categories found in database.")

    # Calculate final pass/fail
    # Need 100 points for full pass (all weights correct)
    passed = (score == 100)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": {
            "actual_categories": actual_categories,
            "expected_categories": expected_categories
        }
    }