#!/usr/bin/env python3
"""
Verifier for binary_bulb_activity@1.

Verifies:
1. Navigation: Agent found and opened the specific activity.
2. Gameplay: Agent completed at least 3 levels (detected via VLM trajectory).
3. Evidence: Agent took the requested screenshot.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Gym-Anything VLM helpers (mock import if running locally without framework)
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback for testing/linting
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(images, prompt): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt to analyze the gameplay progression
VLM_PROMPT = """
You are analyzing a screen recording of a user playing the 'Binary Bulbs' educational game in GCompris.

In this game:
- A decimal number is shown (e.g., '12').
- A row of light bulbs represents binary bits (1, 2, 4, 8, etc.).
- The user must turn on the correct bulbs to sum up to the number.
- When correct, the game advances to the next level/number.

Look at the sequence of screenshots and determine:
1. Did the user successfully navigate to and open the 'Binary Bulbs' activity? (Look for light bulbs and a number).
2. Did the user attempt to solve the puzzles? (Look for bulbs changing state).
3. Did the user complete multiple levels? (Look for the target number changing, e.g., from 5 to 12).

Provide a JSON response:
{
  "activity_opened": true/false,
  "bulbs_visible": true/false,
  "levels_completed_count_estimate": 0,
  "different_numbers_seen": ["list", "of", "numbers"],
  "gameplay_progression_observed": true/false,
  "confidence": "low/medium/high"
}
"""

def verify_binary_bulb_activity(traj, env_info, task_info):
    """
    Verify the binary bulbs task using VLM trajectory analysis and file checks.
    """
    # 1. Setup and Load Results
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Criterion: App Running (10 pts)
    if result_data.get("app_was_running", False):
        score += 10
        feedback_parts.append("GCompris was running.")
    else:
        feedback_parts.append("GCompris was NOT running at the end.")

    # 3. Criterion: Agent Screenshot (15 pts)
    # Checks if the agent followed the instruction to save a screenshot
    screenshot_exists = result_data.get("agent_screenshot_exists", False)
    screenshot_time = result_data.get("agent_screenshot_timestamp", 0)
    task_start = result_data.get("task_start", 0)
    
    if screenshot_exists:
        if screenshot_time > task_start:
            score += 15
            feedback_parts.append("Agent screenshot saved correctly.")
        else:
            score += 5 # Created but stale?
            feedback_parts.append("Agent screenshot exists but timestamp is invalid.")
    else:
        feedback_parts.append("Agent did not save the requested screenshot.")

    # 4. Criterion: VLM Trajectory Analysis (75 pts total)
    # We use trajectory frames to verify the actual gameplay workflow
    frames = sample_trajectory_frames(traj, n=6)
    final_frame = get_final_screenshot(traj)
    
    if final_frame:
        frames.append(final_frame)

    if not frames:
        return {"passed": False, "score": score, "feedback": "No video trajectory available for verification."}

    vlm_result = query_vlm(images=frames, prompt=VLM_PROMPT)
    
    if not vlm_result.get("success"):
        feedback_parts.append("VLM verification failed.")
        # Fallback: if we have the screenshot file, give partial credit
        if screenshot_exists and score < 50:
            score += 20 
        return {"passed": False, "score": score, "feedback": " ".join(feedback_parts)}

    analysis = vlm_result.get("parsed", {})
    
    # Scoring based on VLM analysis
    
    # Activity Opened (25 pts)
    if analysis.get("activity_opened") or analysis.get("bulbs_visible"):
        score += 25
        feedback_parts.append("Binary Bulbs activity launched.")
    else:
        feedback_parts.append("Could not confirm Binary Bulbs activity was opened.")
    
    # Progression/Levels (50 pts)
    # We look for evidence of multiple levels (different numbers seen)
    unique_numbers = len(analysis.get("different_numbers_seen", []))
    estimated_levels = analysis.get("levels_completed_count_estimate", 0)
    progression = analysis.get("gameplay_progression_observed", False)

    # Use the max of distinct numbers seen or estimated count
    level_evidence = max(unique_numbers, estimated_levels)
    
    if level_evidence >= 3:
        score += 50
        feedback_parts.append(f"Confirmed completion of {level_evidence} levels.")
    elif level_evidence == 2:
        score += 35
        feedback_parts.append("Confirmed completion of 2 levels.")
    elif level_evidence == 1 or progression:
        score += 20
        feedback_parts.append("Confirmed completion of 1 level or progression observed.")
    else:
        feedback_parts.append("No clear evidence of level progression.")

    # Final Pass Check
    # Pass if score >= 60 AND activity was definitively opened
    passed = (score >= 60) and (analysis.get("activity_opened") or analysis.get("bulbs_visible"))

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback_parts),
        "details": analysis
    }