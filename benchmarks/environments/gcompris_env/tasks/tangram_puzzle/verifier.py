#!/usr/bin/env python3
"""
Verifier for Tangram Puzzle task.

Verification Strategy:
1. VLM Trajectory Analysis (Primary):
   - Verify navigation from main menu -> Puzzle category -> Tangram.
   - Verify pieces were moved (interaction).
   - Verify puzzle completion (pieces match target outline).
2. Programmatic Checks (Secondary):
   - GCompris running at end.
   - internal DB modification (indicates activity recorded).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tangram_puzzle(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load exported results
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
    
    # 2. Programmatic Checks (20 points max)
    if result.get("app_running", False):
        score += 5
        feedback_parts.append("GCompris running")
    
    if result.get("db_modified", False):
        score += 10
        feedback_parts.append("Activity recorded (DB modified)")
    elif result.get("db_size_change_bytes", 0) != 0:
        score += 5
        feedback_parts.append("DB size changed")
        
    if os.path.basename(result.get("final_screenshot_path", "")) == "tangram_final.png":
        score += 5
        feedback_parts.append("Final screenshot captured")

    # 3. VLM Verification (80 points max)
    # We need to verify the PROCESS (navigation) and the RESULT (puzzle solved)
    frames = sample_trajectory_frames(traj, n=5)
    final_screenshot = get_final_screenshot(traj)
    
    if not frames:
        return {"passed": False, "score": score, "feedback": "No trajectory frames available"}

    # Prompt for Navigation/Process
    process_prompt = """
    You are verifying a user interacting with GCompris educational software.
    Look at this sequence of screenshots.
    
    The user should:
    1. Start at the Main Menu (colorful icons).
    2. Click the 'Puzzle' category (usually a puzzle piece icon).
    3. Click the 'Tangram' activity (shapes forming a figure).
    4. Move geometric shapes (triangles, squares) to fit a silhouette.
    
    Did the user perform these steps?
    """
    
    process_result = query_vlm(images=frames, prompt=process_prompt)
    process_parsed = process_result.get("parsed", {}) # Assuming generic VLM response handling
    # Since specific schema parsing might depend on the VLM tool wrapper, we'll do a simple text check if parsed isn't available or structure is loose.
    # But sticking to the pattern:
    
    # Let's use a structured prompt for better scoring
    structured_prompt = """
    Analyze these screenshots of a GCompris session.
    Return JSON with:
    {
      "main_menu_visible": boolean,
      "puzzle_category_accessed": boolean,
      "tangram_activity_opened": boolean,
      "pieces_moved": boolean,
      "puzzle_solved": boolean
    }
    
    "puzzle_solved" means the geometric pieces (red, blue, green, etc.) form a complete figure matching a target silhouette, or a success message/animation is visible.
    """
    
    vlm_response = query_vlm(images=frames + [final_screenshot], prompt=structured_prompt)
    
    if not vlm_response.get("success"):
        feedback_parts.append("VLM analysis failed")
    else:
        analysis = vlm_response.get("parsed", {})
        
        if analysis.get("main_menu_visible"):
            score += 10
            feedback_parts.append("Started at menu")
            
        if analysis.get("puzzle_category_accessed"):
            score += 10
            feedback_parts.append("Found Puzzle category")
            
        if analysis.get("tangram_activity_opened"):
            score += 20
            feedback_parts.append("Opened Tangram")
            
        if analysis.get("pieces_moved"):
            score += 20
            feedback_parts.append("Interacted with pieces")
            
        if analysis.get("puzzle_solved"):
            score += 20
            feedback_parts.append("Puzzle solved")
    
    passed = score >= 60 and analysis.get("tangram_activity_opened", False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ", ".join(feedback_parts)
    }