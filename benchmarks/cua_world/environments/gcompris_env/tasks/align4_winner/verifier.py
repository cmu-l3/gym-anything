#!/usr/bin/env python3
"""
Verifier for GCompris Align 4 Winner task.

Criteria:
1. Agent navigated to and played Align 4 (VLM Trajectory).
2. Agent won the game (VLM Trajectory/Final State).
3. Agent saved the evidence screenshot as requested (File check).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_align4_winner(traj, env_info, task_info):
    """
    Verifies that the agent played Align 4 and won.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # =========================================================
    # CRITERION 1: Evidence Screenshot (20 points)
    # =========================================================
    if result.get("user_screenshot_exists") and result.get("user_screenshot_created_during_task"):
        if result.get("user_screenshot_size", 0) > 10240:  # >10KB
            score += 20
            feedback_parts.append("Evidence screenshot saved successfully.")
        else:
            score += 10
            feedback_parts.append("Evidence screenshot saved but file is very small.")
    else:
        feedback_parts.append("Evidence screenshot NOT found or not created during task.")

    # =========================================================
    # CRITERION 2: VLM Trajectory Verification (80 points)
    # =========================================================
    
    # We examine trajectory frames to verify gameplay and winning state
    frames = sample_trajectory_frames(traj, n=6)
    final_screen = get_final_screenshot(traj)
    
    # Add final screen to frames if not present
    all_images = frames + [final_screen] if final_screen else frames

    if not all_images:
        return {"passed": False, "score": score, "feedback": "No trajectory images available."}

    prompt = """
    You are verifying an agent playing the 'Align 4' (Connect 4) game in GCompris.
    
    Look at the sequence of screenshots.
    
    1. GAME_PLAYED: Do you see the 'Align 4' game board (a grid with falling red/yellow tokens)?
    2. PROGRESSION: Does the board change over time (more tokens added)?
    3. VICTORY: Does the agent WIN? Look for:
       - A line of 4 matching tokens (horizontal, vertical, or diagonal)
       - A 'Great', 'Congratulations', or 'You Win' message/animation
       - A Tux/penguin character appearing in a victory pose
       - The sidebar turning into a success indicator
    
    Return JSON:
    {
        "game_played": boolean,
        "progression_observed": boolean,
        "victory_detected": boolean,
        "confidence": "high/medium/low",
        "reason": "description of what you see"
    }
    """

    try:
        vlm_resp = query_vlm(prompt=prompt, images=all_images)
        vlm_data = vlm_resp.get("parsed", {})
        
        # Scoring based on VLM
        if vlm_data.get("game_played"):
            score += 20
            feedback_parts.append("VLM confirms Align 4 game was accessed.")
            
            if vlm_data.get("progression_observed"):
                score += 20
                feedback_parts.append("VLM confirms gameplay progression.")
                
                if vlm_data.get("victory_detected"):
                    score += 40
                    feedback_parts.append("VLM confirms GAME WON.")
                else:
                    feedback_parts.append("VLM did NOT detect a clear victory state.")
            else:
                feedback_parts.append("VLM did not see tokens being added/gameplay.")
        else:
            feedback_parts.append("VLM did not identify the Align 4 game board.")
            
        logger.info(f"VLM Analysis: {vlm_data}")

    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        feedback_parts.append("VLM verification failed.")

    # =========================================================
    # CHECK DB LOGS (Bonus confirmation, doesn't affect score if missing due to version diffs)
    # =========================================================
    db_logs = result.get("db_logs", "")
    if "align4" in str(db_logs).lower() or "connect4" in str(db_logs).lower():
        feedback_parts.append("Internal logs confirm Align 4 activity.")

    # Final tally
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }