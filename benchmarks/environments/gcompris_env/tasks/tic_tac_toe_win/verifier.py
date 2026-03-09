#!/usr/bin/env python3
"""
Verifier for Tic-Tac-Toe Win task (`tic_tac_toe_win@1`).

Strategy:
1. File Verification (25 pts): Check if `tic_tac_toe_victory.png` was created during the task.
2. VLM Content Verification (35 pts): Analyze the user-saved screenshot (or final screen) to confirm a win.
3. VLM Trajectory Verification (40 pts): Verify the agent navigated correctly and played the game.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tic_tac_toe_win(traj, env_info, task_info):
    """
    Verify the agent won Tic-Tac-Toe against the computer.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # ================================================================
    # 1. Get Task Metadata & Result JSON
    # ================================================================
    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_screenshot_path', '/home/ga/tic_tac_toe_victory.png')
    
    # Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # ================================================================
    # 2. File Verification (25 points)
    # ================================================================
    file_exists = result.get('victory_file_exists', False)
    file_fresh = result.get('victory_file_created_during_task', False)
    file_size = result.get('victory_file_size', 0)
    
    evidence_image_path = None
    
    if file_exists:
        if file_size > 1000: # Min 1KB
            score += 10
            feedback_parts.append("Screenshot file exists.")
            if file_fresh:
                score += 15
                feedback_parts.append("Screenshot created during task.")
                
                # Retrieve this image for VLM analysis
                temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                try:
                    copy_from_env(expected_path, temp_img.name)
                    evidence_image_path = temp_img.name
                except:
                    logger.warning("Could not copy evidence image despite it existing")
            else:
                feedback_parts.append("Screenshot is old (pre-task).")
        else:
            feedback_parts.append("Screenshot file is empty/too small.")
    else:
        feedback_parts.append("No screenshot file saved.")

    # ================================================================
    # 3. VLM Content Verification (35 points)
    # Check if the "victory" is visible in the saved file or final screen
    # ================================================================
    
    # Prefer the user-saved file, fallback to final screen
    image_to_check = evidence_image_path if evidence_image_path else get_final_screenshot(traj)
    
    if image_to_check:
        prompt_content = """
        Examine this screenshot from GCompris Tic-Tac-Toe.
        1. Is the Tic-Tac-Toe board visible (3x3 grid)?
        2. Is there a winning line (three marks in a row/column/diagonal) for the player?
        3. Is there a victory indication (congratulations text, flower icon, bonus animation, or 'OK' button)?
        
        Respond JSON: {"board_visible": bool, "win_detected": bool, "victory_indicator": bool}
        """
        
        vlm_res = query_vlm(prompt=prompt_content, image=image_to_check)
        
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('board_visible'):
                score += 10
                feedback_parts.append("Board visible in screenshot.")
            if parsed.get('win_detected') or parsed.get('victory_indicator'):
                score += 25
                feedback_parts.append("Win/Victory confirmed visually.")
            else:
                feedback_parts.append("No obvious win detected in screenshot.")
        else:
            feedback_parts.append("VLM content check failed.")
            
        # Cleanup temp file
        if evidence_image_path and os.path.exists(evidence_image_path):
            os.unlink(evidence_image_path)
    else:
        feedback_parts.append("No image available for content verification.")

    # ================================================================
    # 4. VLM Trajectory Verification (40 points)
    # Verify the workflow: Menu -> Strategy -> Game
    # ================================================================
    frames = sample_trajectory_frames(traj, n=6)
    
    prompt_traj = """
    Analyze these chronological screenshots of a user using GCompris.
    The goal is to navigate to the Strategy category, open Tic-Tac-Toe, and play.
    
    Look for:
    1. Start: Main menu (colorful icons).
    2. Navigation: Switching to 'Strategy' category (chess piece icon).
    3. Game: Tic-Tac-Toe board appearing.
    4. Play: Pieces (X/O) being added to the board over time.
    
    Respond JSON: {
        "main_menu_seen": bool,
        "strategy_category_seen": bool,
        "tictactoe_board_seen": bool,
        "gameplay_progression": bool
    }
    """
    
    vlm_traj = query_vlm(prompt=prompt_traj, images=frames)
    
    if vlm_traj.get('success'):
        parsed = vlm_traj.get('parsed', {})
        
        if parsed.get('main_menu_seen'):
            score += 5
        if parsed.get('strategy_category_seen') or parsed.get('tictactoe_board_seen'):
            score += 15
            feedback_parts.append("Navigated to game.")
        
        if parsed.get('gameplay_progression'):
            score += 20
            feedback_parts.append("Gameplay progression observed.")
        else:
            feedback_parts.append("No gameplay progression seen.")
    else:
        feedback_parts.append("VLM trajectory check failed.")

    # ================================================================
    # Final Scoring
    # ================================================================
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }