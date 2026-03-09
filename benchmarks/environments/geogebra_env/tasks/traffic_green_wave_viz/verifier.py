#!/usr/bin/env python3
"""
Verifier for Traffic Green Wave Visualization task.

Scoring (100 points total):
1. File created during task: 10 pts
2. Slider 'offset' created: 10 pts
3. Intersections modeled (y=80, 160, etc.): 20 pts
4. Periodic Red Zones (Sequence command): 30 pts
5. Car Trajectory (Line y=11.2x): 20 pts
6. VLM Check (Visual Pattern): 10 pts

Pass Threshold: 70 points
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70

def verify_traffic_green_wave_viz(traj, env_info, task_info):
    """Verify the Green Wave task using XML analysis and VLM."""
    
    # 1. Setup and load JSON result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    result = {}
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Programmatic Verification (90 points)
    # ---------------------------------------------------------

    # Criterion 1: File created (10 pts)
    if result.get('file_found') and result.get('file_created_during_task'):
        score += 10
        feedback_parts.append("File created (+10)")
    elif result.get('file_found'):
        feedback_parts.append("File found but old (0/10)")
    else:
        feedback_parts.append("File not found (0/10)")

    # Criterion 2: Slider present (10 pts)
    if result.get('has_slider'):
        score += 10
        feedback_parts.append(f"Slider '{result.get('slider_label','')}' found (+10)")
    else:
        feedback_parts.append("No slider found (0/10)")

    # Criterion 3: Intersections (20 pts)
    # Require at least 3 of the 4 non-zero intersections to be identifiable in XML
    y_found = result.get('intersection_y_coords', [])
    if len(y_found) >= 3:
        score += 20
        feedback_parts.append(f"Intersections found at {y_found} (+20)")
    elif len(y_found) > 0:
        score += 10
        feedback_parts.append(f"Some intersections found {y_found} (+10)")
    else:
        feedback_parts.append("Intersection geometry missing (0/20)")

    # Criterion 4: Sequence Command (30 pts) - Critical for efficiency
    if result.get('has_sequence'):
        score += 30
        feedback_parts.append("Sequence command used for periodic signals (+30)")
    else:
        feedback_parts.append("Sequence command NOT used (manual polygons?) (0/30)")

    # Criterion 5: Car Trajectory (20 pts)
    if result.get('has_car_trajectory'):
        score += 20
        feedback_parts.append("Car trajectory line (slope ~11.2) found (+20)")
    else:
        feedback_parts.append("Car trajectory line not found (0/20)")

    # ---------------------------------------------------------
    # VLM Verification (10 points)
    # ---------------------------------------------------------
    # Check if the final screenshot looks like a space-time diagram
    
    vlm_score = 0
    vlm_reason = "VLM check skipped"
    
    try:
        final_screenshot = get_final_screenshot(traj)
        if final_screenshot:
            prompt = """
            You are verifying a GeoGebra 'Space-Time Diagram' for traffic flow.
            The image should show:
            1. A 2D plot with multiple horizontal rows of repeating bars (red/green light intervals).
            2. These rows should be stacked vertically (representing distance).
            3. A straight line (car trajectory) cutting diagonally through the graph.
            4. The repeating bars usually look like a 'ladder' or 'staircase' pattern if synchronized.
            
            Does the image show a Space-Time diagram with horizontal repeating bars and a diagonal line?
            Respond JSON: {"is_space_time_diagram": bool, "has_diagonal_line": bool, "reason": str}
            """
            
            vlm_res = query_vlm(prompt=prompt, image=final_screenshot)
            
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('is_space_time_diagram'):
                    vlm_score = 10
                    vlm_reason = "Visual diagram verified"
                else:
                    vlm_reason = f"Visual check failed: {parsed.get('reason')}"
            else:
                vlm_reason = "VLM query failed"
        else:
            vlm_reason = "No final screenshot"
            
    except Exception as e:
        vlm_reason = f"VLM error: {str(e)}"

    score += vlm_score
    feedback_parts.append(f"Visual check: {vlm_reason} (+{vlm_score})")

    # Final Result
    passed = score >= PASS_THRESHOLD
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }