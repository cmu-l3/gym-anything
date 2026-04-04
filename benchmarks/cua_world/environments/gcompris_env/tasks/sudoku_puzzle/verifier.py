#!/usr/bin/env python3
"""
Verifier for Sudoku Puzzle task in GCompris.

Verification Strategy:
1. **App State (Programmatic)**: Check if GCompris is still running and if configuration/data files were modified (indicating interaction).
2. **Visual Verification (VLM)**: Analyze trajectory frames to confirm:
   - Navigation to the Puzzle category.
   - Opening the Sudoku activity.
   - Interaction with the grid (cells filled).
   - Successful completion (Bonus/Congratulations animation).

This hybrid approach prevents "do nothing" (file checks) and ensures the specific task goal was met (VLM checks for the "Bonus" state).
"""

import json
import os
import sys
import tempfile
import logging
from typing import Dict, Any

# Import VLM utilities provided by the framework
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback for local testing
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sudoku_puzzle(traj, env_info, task_info):
    """
    Verifies that the agent completed the GCompris Sudoku puzzle.
    """
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy unavailable"}

    # Load programmatic result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Programmatic Signals
    app_running = result_data.get("app_running", False)
    modified_files = result_data.get("modified_file_count", 0)
    
    score = 0
    feedback = []

    # Criterion A: App Running (5 pts)
    if app_running:
        score += 5
        feedback.append("GCompris application is running.")
    else:
        feedback.append("GCompris was closed (should remain open).")

    # Criterion B: Interaction Evidence (File Mods) (10 pts)
    # GCompris saves config/progress on exit or level completion. 
    # Even if open, some temp files might change or be created.
    if modified_files > 0:
        score += 10
        feedback.append(f"Detected file system interaction ({modified_files} files modified).")
    else:
        feedback.append("No file modification detected (may indicate lack of deep interaction).")

    # 3. VLM Verification (Crucial for Game Logic)
    # We need to verify the specific game state which isn't easily accessible via files.
    
    frames = sample_trajectory_frames(traj, n=5)
    final_screen = get_final_screenshot(traj)
    
    if not frames and not final_screen:
        return {"passed": False, "score": score, "feedback": "No visual evidence available."}

    # Prompt designed to check specific milestones
    vlm_prompt = """
    You are verifying an agent playing the Sudoku activity in GCompris educational software.
    
    Analyze the provided screenshots (chronological trajectory + final state).
    Look for these specific stages:
    
    1. **Menu Navigation**: Did the screen change from the main menu (icons) to a specific category or activity?
    2. **Sudoku Activity**: Is the Sudoku game visible? (A grid, usually 4x4, with colorful icons/images).
    3. **Solved/Bonus**: Is the "Congratulations" or "Bonus" animation visible? (Often a flower, star, or smiling character appearing over the grid).
    
    JSON Response Format:
    {
        "navigated_from_menu": boolean,
        "sudoku_grid_seen": boolean,
        "puzzle_interaction_seen": boolean,
        "bonus_animation_visible": boolean,
        "confidence": "high/medium/low",
        "reasoning": "string"
    }
    """
    
    # Combine frames for context
    images_to_check = frames + [final_screen] if final_screen else frames
    vlm_response = query_vlm(prompt=vlm_prompt, images=images_to_check)
    
    vlm_passed = False
    if vlm_response.get("success"):
        parsed = vlm_response.get("parsed", {})
        
        # Criterion C: Navigation (15 pts)
        if parsed.get("navigated_from_menu"):
            score += 15
            feedback.append("Successfully navigated away from main menu.")
            
        # Criterion D: Found Sudoku (30 pts)
        if parsed.get("sudoku_grid_seen"):
            score += 30
            feedback.append("Located and opened Sudoku activity.")
        else:
            feedback.append("Could not confirm Sudoku activity was opened.")

        # Criterion E: Completion / Bonus (40 pts)
        # This implies interaction was successful
        if parsed.get("bonus_animation_visible"):
            score += 40
            feedback.append("Puzzle solved! Bonus animation detected.")
            vlm_passed = True
        elif parsed.get("puzzle_interaction_seen"):
            score += 10
            feedback.append("Interaction with puzzle detected, but completion not confirmed.")
        else:
            feedback.append("No evidence of puzzle completion.")
            
        logger.info(f"VLM Reasoning: {parsed.get('reasoning')}")
    else:
        feedback.append("Visual verification failed (VLM error).")

    # Final Pass Logic
    # Pass if score >= 70 (Requires at least finding Sudoku + significant interaction or completion)
    # AND App is running
    passed = (score >= 70) and app_running

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }