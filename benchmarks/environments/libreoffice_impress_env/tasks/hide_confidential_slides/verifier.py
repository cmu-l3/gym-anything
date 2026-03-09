#!/usr/bin/env python3
"""
Verifier for hide_confidential_slides task.

Verifies:
1. File exists and was modified/saved
2. Total slide count matches original (8 slides) - ensures no deletion
3. Target slides (3, 5, 7) are marked as hidden
4. Non-target slides are NOT hidden
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hide_confidential_slides(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring config
    target_hidden = set([3, 5, 7])
    target_visible = set([1, 2, 4, 6, 8])
    expected_total = 8
    
    score = 0
    feedback_parts = []
    
    # 1. File Existence & Validity (20 pts)
    if result.get('file_exists') and not result.get('slide_analysis', {}).get('error'):
        score += 10
        feedback_parts.append("Presentation file found and valid")
    else:
        return {"passed": False, "score": 0, "feedback": "No valid presentation file found"}
        
    if result.get('modified_during_task') or result.get('content_changed'):
        score += 10
        feedback_parts.append("File was saved/modified")
    else:
        feedback_parts.append("File timestamp not updated (did you save?)")
        
    analysis = result.get('slide_analysis', {})
    total_slides = analysis.get('total_slides', 0)
    hidden_list = analysis.get('hidden_indices', [])
    hidden_set = set(hidden_list)
    
    # 2. Structure Preservation (15 pts)
    if total_slides == expected_total:
        score += 15
        feedback_parts.append(f"Slide count correct ({total_slides})")
    else:
        feedback_parts.append(f"Incorrect slide count: {total_slides} (expected {expected_total}) - Do not delete slides!")
        
    # 3. Target Slides Hidden (45 pts, 15 each)
    hidden_correctly = 0
    for idx in target_hidden:
        if idx in hidden_set:
            score += 15
            hidden_correctly += 1
        else:
            feedback_parts.append(f"Slide {idx} NOT hidden")
    
    if hidden_correctly == 3:
        feedback_parts.append("All confidential slides hidden")
        
    # 4. Non-target Slides Visible (20 pts)
    incorrectly_hidden = hidden_set - target_hidden
    if len(incorrectly_hidden) == 0:
        score += 20
        feedback_parts.append("Other slides remain visible")
    else:
        feedback_parts.append(f"Wrong slides hidden: {list(incorrectly_hidden)}")
        # Partial penalty
        penalty = len(incorrectly_hidden) * 5
        score += max(0, 20 - penalty)

    # Pass threshold
    passed = score >= 65 and hidden_correctly >= 2 and total_slides == expected_total

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }