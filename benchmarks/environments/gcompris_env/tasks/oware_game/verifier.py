#!/usr/bin/env python3
"""
Verifier for Oware (Mancala) Strategy Game task.

Criteria:
1. GCompris was active and data was modified (indicates interaction).
2. VLM Trajectory Analysis:
   - Agent navigated to Strategy category.
   - Oware board was visible.
   - Game state changed (seeds moved).
   - Agent won (Victory screen/score).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_oware_game(traj, env_info, task_info):
    """
    Verify the Oware game task using trajectory analysis and file evidence.
    """
    # 1. Setup & File Evidence Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Programmatic Scoring (Base Points)
    score = 0
    feedback_parts = []
    
    # Check if app was running (10 pts)
    if result.get('app_was_running', False):
        score += 10
        feedback_parts.append("App was running.")
    
    # Check if screen changed (10 pts)
    if result.get('screen_changed', False):
        score += 10
        feedback_parts.append("Screen content changed.")
    else:
        return {"passed": False, "score": 0, "feedback": "No visual change detected (did nothing)."}

    # Check if database was modified (Evidence of level completion/progress) (10 pts)
    if result.get('db_modified', False):
        score += 10
        feedback_parts.append("Game progress data recorded.")
    
    # 3. VLM Trajectory Verification (70 pts)
    # We need to check the flow: Menu -> Strategy -> Oware Board -> Gameplay -> Win
    
    frames = sample_trajectory_frames(traj, n=6)
    final_frame = get_final_screenshot(traj)
    
    # Prompt for VLM
    prompt = """
    You are verifying if an agent successfully played the game 'Oware' (also known as Mancala or Awele) in GCompris.
    
    Please analyze these screenshots from the agent's session (ordered chronologically) and the final screenshot.
    
    Look for the following milestones:
    1. **Navigation**: Did the agent open the 'Strategy' category (usually chess/checkers icons)?
    2. **Game Launch**: Is the Oware board visible? (Two rows of 6 circular pits with seeds/pebbles).
    3. **Gameplay**: Did the board state change? (Seeds moving, counts changing in pits).
    4. **Victory**: Is there a 'Congratulations', 'You Won', or a score screen showing the player (bottom) winning?
    
    The Oware board looks like a wooden board with holes. The player controls the bottom row.
    
    Return JSON:
    {
        "strategy_category_seen": boolean,
        "oware_board_seen": boolean,
        "gameplay_detected": boolean,
        "victory_detected": boolean,
        "confidence": "low/medium/high",
        "explanation": "Brief description of what happened."
    }
    """
    
    vlm_result = query_vlm(images=frames + [final_frame], prompt=prompt)
    
    vlm_data = vlm_result.get('parsed', {})
    if not vlm_result.get('success'):
        feedback_parts.append("VLM verification failed to execute.")
        # Fallback partial credit if DB modified
        if score >= 30: 
            return {"passed": False, "score": score, "feedback": " ".join(feedback_parts)}
    
    # VLM Scoring logic
    vlm_score = 0
    
    if vlm_data.get('strategy_category_seen', False):
        vlm_score += 10
        feedback_parts.append("Strategy category found.")
        
    if vlm_data.get('oware_board_seen', False):
        vlm_score += 20
        feedback_parts.append("Oware game launched.")
        
    if vlm_data.get('gameplay_detected', False):
        vlm_score += 20
        feedback_parts.append("Gameplay moves detected.")
        
    if vlm_data.get('victory_detected', False):
        vlm_score += 20
        feedback_parts.append("Victory condition met.")
    else:
        feedback_parts.append("Victory not detected.")

    score += vlm_score

    # 4. Final Verdict
    # Pass threshold: 70 points. Must have at least launched game and played (gameplay detected).
    # Winning is desired for full score but playing correctly is partial pass.
    
    passed = score >= 70 and vlm_data.get('oware_board_seen', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": vlm_data
    }