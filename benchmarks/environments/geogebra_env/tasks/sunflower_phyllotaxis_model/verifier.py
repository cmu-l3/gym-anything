#!/usr/bin/env python3
"""
Verifier for Sunflower Phyllotaxis Model task.

Criteria:
1. File exists and created during task (10 pts)
2. Slider for angle exists (20 pts)
3. Sequence command used (30 pts)
4. List size adequate (>400) (20 pts)
5. Dynamic linkage (List depends on slider) (20 pts)
"""

import json
import os
import logging
import tempfile

logger = logging.getLogger(__name__)

def verify_sunflower_model(traj, env_info, task_info):
    """Verify sunflower phyllotaxis task."""
    
    # 1. Setup copy from env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy unavailable"}
    
    # 2. Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result retrieval failed: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # 3. Score
    score = 0
    feedback = []
    
    # Criterion 1: File created (10 pts)
    if result.get("file_found") and result.get("file_created_during_task"):
        score += 10
        feedback.append("File created successfully (+10).")
    elif result.get("file_found"):
        feedback.append("File found but not created during this session (0).")
    else:
        feedback.append("File not found (0).")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: Slider present (20 pts)
    if result.get("has_slider"):
        score += 20
        feedback.append(f"Slider found (label: {result.get('slider_label', 'unknown')}) (+20).")
    else:
        feedback.append("No slider found. A slider is required for the angle (0).")
        
    # Criterion 3: Sequence command (30 pts)
    if result.get("has_sequence"):
        score += 30
        feedback.append("Sequence command used (+30).")
    else:
        feedback.append("Sequence command not found. You must use Sequence() to generate the points (0).")
        
    # Criterion 4: List size (20 pts)
    # The XML parsing tries to find the 'to' argument. If not found but Sequence exists,
    # we might give partial credit if the command is complex enough, but strict check is better.
    list_size = result.get("list_size", 0)
    if list_size >= 450:
        score += 20
        feedback.append(f"List size adequate ({list_size} points) (+20).")
    elif list_size > 0:
        score += 10
        feedback.append(f"List size {list_size} is smaller than requested 500 (+10).")
    elif result.get("has_sequence"):
        # If we have sequence but couldn't parse size, assumes it's likely okay if dynamic check passes
        score += 10
        feedback.append("Sequence found but size could not be verified (+10).")
    else:
        feedback.append("List size check failed (0).")
        
    # Criterion 5: Dynamic Linkage (20 pts)
    if result.get("is_dynamic"):
        score += 20
        feedback.append("Dynamic linkage verified: Sequence depends on Slider (+20).")
    else:
        feedback.append("Dynamic linkage not found. The sequence must reference the slider variable (0).")
        
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }