#!/usr/bin/env python3
"""
Verifier for setup_cinema_scope_scene task.

Scoring Breakdown (100 pts total):
1. Scene File Creation (25 pts)
   - File exists at correct path: 15 pts
   - File created during task: 10 pts
2. Scene Configuration (15 pts)
   - .tnz file contains correct resolution/fps data: 15 pts
3. Render Verification (60 pts)
   - Rendered file exists: 15 pts
   - Dimensions exactly 2048x858: 30 pts (CRITICAL)
   - Render created during task: 15 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_setup_cinema_scope_scene(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Scene File Check (25 pts)
    if result.get("scene_exists", False):
        score += 15
        feedback_parts.append("Scene file created")
        if result.get("scene_created_during_task", False):
            score += 10
            feedback_parts.append("Scene file fresh")
        else:
            feedback_parts.append("Scene file stale")
    else:
        feedback_parts.append("Scene file NOT found at expected path")

    # 2. Scene Content Check (15 pts)
    # This checks if the .tnz file textually contains the target resolution
    if result.get("scene_content_res_match", False):
        score += 15
        feedback_parts.append("Scene data confirms 2K Scope settings")
    else:
        feedback_parts.append("Scene data missing target resolution")

    # 3. Render Verification (60 pts)
    render_exists = result.get("render_exists", False)
    render_width = result.get("render_width", 0)
    render_height = result.get("render_height", 0)
    
    if render_exists:
        score += 15
        feedback_parts.append("Test render found")
        
        # Resolution Check - Critical
        target_w, target_h = 2048, 858
        if render_width == target_w and render_height == target_h:
            score += 30
            feedback_parts.append(f"Resolution CORRECT ({target_w}x{target_h})")
        else:
            feedback_parts.append(f"Resolution INCORRECT (Found {render_width}x{render_height}, expected {target_w}x{target_h})")
            
        # Timestamp Check
        if result.get("render_created_during_task", False):
            score += 15
        else:
            feedback_parts.append("Render file is stale")
    else:
        feedback_parts.append("No test render found in output directory")

    # Pass logic
    # Must have correct resolution render AND scene file
    passed = (score >= 60) and (render_width == 2048) and (render_height == 858)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }