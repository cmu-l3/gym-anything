#!/usr/bin/env python3
"""
Verifier for Coordinate Plane Activity task.
Verifies the creation of a mathematical flipchart with specific content.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_coordinate_plane_activity(traj, env_info, task_info):
    """
    Verify the coordinate plane flipchart.
    
    Scoring Breakdown (100 pts total):
    1. File checks (15 pts): Exists, valid format
    2. Page count (10 pts): Exactly 2 pages
    3. Page 1 Content (15 pts): Title "Plotting Ordered Pairs" (10), "coordinate plane" (5)
    4. Page 2 Structure (20 pts): X/Y labels (10), Quadrant labels I-IV (10)
    5. Page 2 Content (30 pts): 
       - 3+ points labeled (15 pts)
       - All 5 points labeled (10 pts bonus)
       - Shapes drawn >= 7 (axes + points) (5 pts)
    6. Timestamp/Anti-gaming (10 pts)
    
    Pass Threshold: 70 points AND File Valid
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy missing"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. File Checks (15 pts)
    if result.get("file_found") and result.get("file_valid"):
        score += 15
        feedback.append("Valid flipchart file found")
    else:
        return {"passed": False, "score": 0, "feedback": "No valid flipchart file found"}

    # 2. Page Count (10 pts)
    page_count = result.get("page_count", 0)
    if page_count == 2:
        score += 10
        feedback.append("Page count correct (2)")
    else:
        feedback.append(f"Incorrect page count: {page_count} (expected 2)")

    # 3. Page 1 Content (15 pts)
    if result.get("has_title"):
        score += 10
        feedback.append("Title 'Plotting Ordered Pairs' found")
    else:
        feedback.append("Title missing")
        
    if result.get("has_instruction"):
        score += 5
        feedback.append("Instruction 'coordinate plane' found")
    else:
        feedback.append("Instruction text missing")

    # 4. Page 2 Structure (20 pts)
    if result.get("has_x_axis") and result.get("has_y_axis"):
        score += 10
        feedback.append("Axes labels (x, y) found")
    elif result.get("has_x_axis") or result.get("has_y_axis"):
        score += 5
        feedback.append("One axis label found")
    else:
        feedback.append("Axes labels missing")
        
    quadrants = result.get("quadrants_count", 0)
    if quadrants >= 4:
        score += 10
        feedback.append("All 4 quadrant labels found")
    elif quadrants >= 2:
        score += 5
        feedback.append(f"Partial quadrant labels found ({quadrants})")
    else:
        feedback.append("Quadrant labels missing")

    # 5. Page 2 Content (30 pts)
    points_found = result.get("points_count", 0)
    if points_found >= 3:
        score += 15
        feedback.append(f"Found {points_found}/5 coordinate labels")
        if points_found == 5:
            score += 10
            feedback.append("All 5 points correctly labeled")
    else:
        feedback.append(f"Only {points_found} points labeled (need 3+)")
        
    shape_count = result.get("shape_count", 0)
    if shape_count >= 7:
        score += 5
        feedback.append(f"Sufficient drawing elements found ({shape_count})")
    else:
        feedback.append(f"Few shapes found ({shape_count}), expected >=7")

    # 6. Anti-gaming (10 pts)
    if result.get("created_during_task"):
        score += 10
        feedback.append("File created during task session")
    else:
        feedback.append("File timestamp invalid (pre-existing file?)")
        score = 0 # Fail if file wasn't created now

    # VLM Sanity Check (Optional but recommended)
    query_vlm = env_info.get('query_vlm')
    final_screenshot = get_final_screenshot(traj)
    if query_vlm and final_screenshot:
        prompt = "Is this an educational flipchart showing a coordinate plane with axes and points?"
        vlm_res = query_vlm(image=final_screenshot, prompt=prompt)
        if vlm_res.get('success') and vlm_res.get('parsed', {}).get('answer') == 'yes':
            feedback.append("VLM visual confirmation passed")
            # Could add bonus points here if needed

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }