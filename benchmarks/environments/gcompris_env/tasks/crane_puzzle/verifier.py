#!/usr/bin/env python3
"""
Verifier for GCompris Crane Puzzle Task.

Verification Strategy:
1. File Check: Verify agent saved the requested screenshot (10 pts) + timestamp check (10 pts).
2. App State: Verify GCompris is still running (5 pts).
3. VLM Trajectory Analysis (75 pts total):
   - Sample frames from the agent's interaction.
   - Confirm navigation to Crane activity.
   - Confirm active manipulation of crane (moving items).
   - Confirm completion of Level 1 and Level 2.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_crane_puzzle(traj, env_info, task_info):
    """
    Verify completion of GCompris Crane Puzzle (Levels 1 & 2).
    """
    # 1. Setup and Helper Functions
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Load task result JSON from container
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    # 2. File and State Verification (25 points)
    
    # Check if agent took the screenshot (10 pts)
    if result_data.get("agent_screenshot_exists", False):
        score += 10
        feedback_parts.append("Screenshot saved.")
        
        # Check anti-gaming timestamp (10 pts)
        if result_data.get("agent_screenshot_created_during_task", False):
            score += 10
            feedback_parts.append("Screenshot created during task.")
        else:
            feedback_parts.append("Screenshot timestamp invalid (pre-dated).")
    else:
        feedback_parts.append("Completion screenshot not found.")

    # Check if app is running (5 pts)
    if result_data.get("app_running", False):
        score += 5
        feedback_parts.append("GCompris running.")
    else:
        feedback_parts.append("GCompris closed unexpectedly.")

    # 3. VLM Trajectory Verification (75 points)
    
    # Sample frames from trajectory + final system screenshot
    frames = sample_trajectory_frames(traj, n=6)
    
    # Retrieve final screenshot if available
    final_screenshot = None
    if result_data.get("system_final_screenshot"):
        temp_final_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(result_data["system_final_screenshot"], temp_final_img.name)
            final_screenshot = temp_final_img.name
            frames.append(final_screenshot)
        except Exception:
            pass # Use trajectory frames only if copy fails

    # Prompt for VLM
    prompt = """
    Analyze these screenshots from a user session in GCompris educational software.
    The user is supposed to play the 'Crane' puzzle activity.
    
    Look for the following visual evidence in the sequence:
    1. **Activity Launch**: Is the 'Crane' activity visible? It features a grid, a crane/hook at the top, colored shapes/items, and directional arrow controls (Up/Down/Left/Right).
    2. **Active Interaction**: Do the screenshots show the crane moving or holding items? Do items change position between frames?
    3. **Level 1 Completion**: Is there evidence of solving the first pattern? (Items placed to match the target pattern on the right, or a success animation/star).
    4. **Level 2 Reached**: Do you see a different, slightly more complex target pattern or grid layout appearing later in the sequence, indicating advancement to the next level?
    5. **Level 2 Completion**: Is there evidence of Level 2 being completed (matching the second target pattern)?

    Provide a JSON response:
    {
        "crane_activity_launched": true/false,
        "active_interaction_observed": true/false,
        "level_1_completed": true/false,
        "level_2_reached": true/false,
        "level_2_completed": true/false,
        "reasoning": "brief explanation of what was observed"
    }
    """

    try:
        vlm_response = query_vlm(images=frames, prompt=prompt)
        
        if vlm_response.get("success"):
            analysis = vlm_response.get("parsed", {})
            
            # Criterion 1: Activity Launched (15 pts)
            if analysis.get("crane_activity_launched"):
                score += 15
                feedback_parts.append("Crane activity launched.")
            
            # Criterion 2: Active Interaction (15 pts)
            if analysis.get("active_interaction_observed"):
                score += 15
                feedback_parts.append("Active interaction with crane observed.")
                
            # Criterion 3: Level 1 Completed (15 pts)
            if analysis.get("level_1_completed"):
                score += 15
                feedback_parts.append("Level 1 completion detected.")
                
            # Criterion 4: Level 2 Reached (15 pts)
            if analysis.get("level_2_reached"):
                score += 15
                feedback_parts.append("Level 2 reached.")
                
            # Criterion 5: Level 2 Completed (15 pts)
            if analysis.get("level_2_completed"):
                score += 15
                feedback_parts.append("Level 2 completion detected.")
            
            feedback_parts.append(f"VLM Analysis: {analysis.get('reasoning', 'No reasoning provided')}")
        else:
            feedback_parts.append("VLM verification failed to process images.")
            
    except Exception as e:
        feedback_parts.append(f"VLM verification error: {str(e)}")

    # Clean up temp file
    if final_screenshot and os.path.exists(final_screenshot):
        os.unlink(final_screenshot)

    # Calculate final status
    # Pass threshold: 50 points (Requires at least opening the activity and some file/state points OR significant progress)
    # The agent MUST have at least opened the activity (VLM check) to pass.
    
    activity_opened = False
    if vlm_response.get("success") and vlm_response.get("parsed", {}).get("crane_activity_launched"):
        activity_opened = True
        
    passed = (score >= 50) and activity_opened

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }