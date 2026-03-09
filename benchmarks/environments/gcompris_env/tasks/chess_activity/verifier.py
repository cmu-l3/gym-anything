#!/usr/bin/env python3
"""
Verifier for chess_activity task.

Verification Strategy:
1. File Check (15 pts): Agent saved a screenshot file that was created during the task.
2. App State (10 pts): GCompris is still running.
3. VLM Verification (75 pts):
   - Navigation (25 pts): Did the agent find and open the Chess activity?
   - Gameplay (25 pts): Is the board in a mid-game state (not starting position)?
   - Progression (25 pts): Do trajectory frames show multiple moves being played?

Pass Threshold: 65 points (requires at least basic gameplay + file save OR perfect gameplay verified by VLM)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM helpers (assumed available in verification environment)
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Mock for testing if environment not available
    def query_vlm(**kwargs): return {"success": False, "error": "VLM module not found"}
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None


def verify_chess_activity(traj, env_info, task_info):
    """
    Verify the agent played chess in GCompris.
    """
    # 1. Retrieve JSON result from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    task_result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to read task result file"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. Check File Evidence (15 pts)
    # Anti-gaming: File must be created *during* the task (screenshot_fresh)
    if task_result.get('screenshot_exists', False):
        if task_result.get('screenshot_fresh', False) and task_result.get('screenshot_valid', False):
            score += 15
            feedback.append("Screenshot saved correctly.")
        else:
            feedback.append("Screenshot exists but is invalid (empty or old timestamp).")
    else:
        feedback.append("No screenshot saved at expected path.")

    # 3. Check App State (10 pts)
    if task_result.get('app_running', False):
        score += 10
        feedback.append("GCompris is running.")
    else:
        feedback.append("GCompris was closed (should remain open).")

    # 4. VLM Verification (75 pts)
    # We use trajectory frames to verify actual gameplay progression
    frames = sample_trajectory_frames(traj, n=6)
    final_screen = get_final_screenshot(traj)
    
    if not frames:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback) + " (No video evidence available)"}

    # Prompt designed to detect "Do Nothing" and verify specific chess context
    vlm_prompt = """
    You are verifying an agent playing Chess in the educational software GCompris.
    
    Analyze these screenshots (chronological order) and the final screenshot.
    
    Check for:
    1. CHESS_FOUND: Is the specific GCompris Chess activity visible? (Look for a 2D chess board with standard pieces).
    2. STARTING_POSITION: Does the board show the initial setup (all pieces in rows 1/2 and 7/8)?
    3. MOVES_MADE: Do you see pieces moving between frames? Are pieces absent from their starting squares?
    4. MID_GAME_STATE: Does the final state show a game in progress (scattered pieces, captures, or development)?
    
    Scoring Criteria:
    - Activity Found: The chess board is visible in at least one frame.
    - Gameplay Evidence: The board state changes between frames (pieces move).
    - Significant Progress: The final board is NOT the starting position (at least 3-4 moves made).
    
    Respond in JSON:
    {
        "chess_activity_found": boolean,
        "pieces_moved": boolean,
        "is_starting_position": boolean,
        "game_in_progress": boolean,
        "confidence": "low|medium|high",
        "reasoning": "string"
    }
    """
    
    vlm_result = query_vlm(prompt=vlm_prompt, images=frames + [final_screen])
    
    vlm_score = 0
    if vlm_result.get('success', False):
        parsed = vlm_result.get('parsed', {})
        
        # Criterion A: Navigation (25 pts)
        if parsed.get('chess_activity_found', False):
            vlm_score += 25
            feedback.append("VLM: Chess activity found.")
            
            # Criterion B: Gameplay Trajectory (25 pts)
            if parsed.get('pieces_moved', False):
                vlm_score += 25
                feedback.append("VLM: Piece movement detected.")
            
            # Criterion C: Final State (25 pts)
            # Must NOT be starting position AND must look like a game in progress
            if parsed.get('game_in_progress', False) and not parsed.get('is_starting_position', True):
                vlm_score += 25
                feedback.append("VLM: Game progress confirmed (not start pos).")
            elif parsed.get('is_starting_position', True):
                feedback.append("VLM: Board appears to be in starting position (no moves played).")
        else:
            feedback.append("VLM: Could not identify Chess activity.")
    else:
        feedback.append("VLM verification failed to run.")

    score += vlm_score

    return {
        "passed": score >= 65,
        "score": score,
        "feedback": " | ".join(feedback)
    }