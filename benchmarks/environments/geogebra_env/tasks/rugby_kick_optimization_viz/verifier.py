#!/usr/bin/env python3
"""
Verifier for Rugby Kick Optimization task.

Scoring (100 points total):
  - File created during task:        10 pts
  - Correct Goal Width (5.6m):       20 pts
  - Correct Try Offset (10m):        20 pts
  - Angle Measured:                  15 pts
  - Function Graph Defined:          20 pts
  - Optimal Point Found (~12.5m):    15 pts

Pass Threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_rugby_kick_optimization_viz(traj, env_info, task_info):
    """Verify the rugby optimization task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
    
    # Load result
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. File Creation (10 pts)
    if result.get("file_found") and result.get("file_created_during_task"):
        score += 10
        feedback_parts.append("File created (+10)")
    elif result.get("file_found"):
        feedback_parts.append("File exists but old timestamp (0/10)")
    else:
        feedback_parts.append("File not found (0/10)")
        
    # 2. Goal Width 5.6m (20 pts)
    if result.get("has_goal_width"):
        score += 20
        feedback_parts.append("Goal width 5.6m modeled (+20)")
    else:
        feedback_parts.append("Goal posts (dist=5.6) not found (0/20)")
        
    # 3. Try Offset 10m (20 pts)
    if result.get("has_try_offset"):
        score += 20
        feedback_parts.append("Try offset 10m modeled (+20)")
    else:
        feedback_parts.append("Try location (dist=10) not found (0/20)")
        
    # 4. Angle Measured (15 pts)
    if result.get("has_angle_measure"):
        score += 15
        feedback_parts.append("Angle measurement found (+15)")
    else:
        feedback_parts.append("No Angle command/object found (0/15)")
        
    # 5. Function Graph (20 pts)
    if result.get("has_function"):
        score += 20
        feedback_parts.append("Optimization function graph found (+20)")
    else:
        feedback_parts.append("No function graph found (0/20)")
        
    # 6. Optimal Point (15 pts)
    if result.get("optimal_point_found"):
        score += 15
        val = result.get("optimal_value_x", "unknown")
        feedback_parts.append(f"Optimal point ~12.5m found (val={val}) (+15)")
    else:
        feedback_parts.append("Optimal point (~12.5) not identified (0/15)")
        
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }