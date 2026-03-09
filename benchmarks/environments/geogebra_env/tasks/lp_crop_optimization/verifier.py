#!/usr/bin/env python3
"""
Verifier for LP Crop Optimization task.

Scoring (100 points total):
  - File created during task:           15 pts
  - Constraints present (>=2):          25 pts
  - Corner points marked (>=3):         25 pts
  - Feasible region indicated:          15 pts
  - Optimal solution annotation:        20 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60


def verify_lp_crop_optimization(traj, env_info, task_info):
    """Verify the Linear Programming Crop Optimization task."""
    
    # 1. Setup feedback mechanism
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    query_vlm = env_info.get('query_vlm')
    
    # 2. Retrieve result from container
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r', encoding='utf-8') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error retrieving result file: {str(e)}"}

    score = 0
    feedback_parts = []
    subscores = {}

    # --- CRITERION 1: File Creation (15 pts) ---
    file_found = result.get('file_found', False)
    created_during = result.get('file_created_during_task', False)
    
    if file_found and created_during:
        score += 15
        subscores["file_valid"] = True
        feedback_parts.append("File created successfully (+15)")
    elif file_found:
        feedback_parts.append("File found but predates task start (0/15)")
    else:
        feedback_parts.append("File 'crop_optimization.ggb' not found (0/15)")

    # --- CRITERION 2: Constraints (25 pts) ---
    constraints = result.get('constraints_found', [])
    if len(constraints) >= 3:
        score += 25
        subscores["constraints"] = "full"
        feedback_parts.append(f"All 3 constraints found: {', '.join(constraints)} (+25)")
    elif len(constraints) >= 2:
        score += 15
        subscores["constraints"] = "partial"
        feedback_parts.append(f"2 constraints found: {', '.join(constraints)} (+15)")
    elif len(constraints) >= 1:
        score += 5
        subscores["constraints"] = "minimal"
        feedback_parts.append(f"1 constraint found: {constraints[0]} (+5)")
    else:
        feedback_parts.append("No correct constraint equations found (0/25)")

    # --- CRITERION 3: Corner Points (25 pts) ---
    corners = result.get('corner_points_found', [])
    unique_corners = len(corners)
    
    if unique_corners >= 4:
        score += 25
        subscores["corners"] = "full"
        feedback_parts.append(f"Found {unique_corners} corner points (+25)")
    elif unique_corners >= 3:
        score += 15
        subscores["corners"] = "good"
        feedback_parts.append(f"Found {unique_corners} corner points (+15)")
    elif unique_corners >= 1:
        score += 5
        subscores["corners"] = "minimal"
        feedback_parts.append(f"Found {unique_corners} corner point (+5)")
    else:
        feedback_parts.append("No correct corner points marked (0/25)")

    # --- CRITERION 4: Feasible Region (15 pts) ---
    if result.get('has_feasible_region', False):
        score += 15
        subscores["region"] = True
        feedback_parts.append("Feasible region visualized (+15)")
    else:
        feedback_parts.append("Feasible region not visualized (polygon/inequality) (0/15)")

    # --- CRITERION 5: Optimal Annotation (20 pts) ---
    if result.get('has_optimal_annotation', False):
        score += 20
        subscores["annotation"] = True
        feedback_parts.append("Optimal solution annotated (+20)")
    else:
        feedback_parts.append("No annotation for optimal solution/profit found (0/20)")

    # --- VLM VERIFICATION (Secondary Signal) ---
    # Only run if we have a file but programmatic checks are borderline
    if query_vlm and score >= 30 and score < 60:
        try:
            frames = sample_trajectory_frames(traj, 4)
            final_scr = get_final_screenshot(traj)
            
            prompt = """
            Look at this sequence of GeoGebra screenshots.
            Does the user create a linear programming graph?
            I am looking for:
            1. Several lines intersecting to form a region.
            2. A shaded region or polygon.
            3. Points marked at the corners.
            
            Answer JSON with: {"looks_like_lp_graph": boolean, "reason": string}
            """
            
            vlm_res = query_vlm(prompt=prompt, images=frames + [final_scr])
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('looks_like_lp_graph', False):
                    score += 10
                    feedback_parts.append("VLM confirms visual graph structure (+10 bonus)")
        except Exception:
            pass

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }