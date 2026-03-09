#!/usr/bin/env python3
"""
Verifier for GCompris Water Cycle Restoration Task.

Verification Strategy:
1. File Evidence (30%): Checks if the agent created the status text file and saved a screenshot.
2. App State (10%): Checks if GCompris was still running.
3. VLM Verification (60%): Analyzes trajectory frames to confirm:
   - Navigation to Science category.
   - Opening of Water Cycle activity.
   - Interaction with components (Sun, Cloud, Tower) turning them active/green.
   - Final state showing a running simulation.
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_water_cycle_restoration(traj, env_info, task_info):
    """
    Verify that the agent restored the water cycle simulation in GCompris.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load File Evidence Result
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # --- Criterion 1: Text File Evidence (20 points) ---
    if result.get("text_file_exists", False):
        if result.get("text_file_created_during_task", False):
            score += 10
            feedback_parts.append("Status file created.")
            if result.get("text_content_match", False):
                score += 10
                feedback_parts.append("Status text correct.")
            else:
                feedback_parts.append("Status text incorrect.")
        else:
            feedback_parts.append("Status file old (anti-gaming).")
    else:
        feedback_parts.append("No status file found.")

    # --- Criterion 2: Screenshot File Evidence (10 points) ---
    # Agent was supposed to save a screenshot manually
    if result.get("screenshot_file_exists", False):
        size = result.get("screenshot_file_size", 0)
        if size > 10000:  # >10KB implies not empty
            score += 10
            feedback_parts.append("Agent screenshot saved.")
        else:
            feedback_parts.append("Agent screenshot empty.")
    else:
        feedback_parts.append("No agent screenshot found.")

    # --- Criterion 3: App Running (10 points) ---
    if result.get("app_was_running", False):
        score += 10
        feedback_parts.append("GCompris running.")
    else:
        feedback_parts.append("GCompris closed early.")

    # --- Criterion 4: VLM Trajectory Verification (60 points) ---
    # We analyze frames to prove work was done
    frames = sample_trajectory_frames(traj, n=5)
    final_screen = get_final_screenshot(traj)
    
    if not frames:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + " | No video evidence."}

    # Prompt designed to check specific visual milestones
    vlm_prompt = """
    You are verifying an agent's interaction with the GCompris educational software 'Water Cycle' activity.
    
    The agent should:
    1. Navigate to the Science category (icon often looks like a test tube or flask).
    2. Open the 'Water Cycle' activity (shows a landscape with water, clouds, sun).
    3. Click on red/inactive components (Sun, Cloud, Water Tower, Treatment Plant) to turn them green/active.
    4. Achieve a state where the water cycle is flowing/animating.

    Examine the sequence of screenshots.
    
    Respond in JSON:
    {
        "science_category_entered": boolean,
        "water_cycle_activity_opened": boolean,
        "components_activated": boolean, 
        "final_state_active": boolean,
        "explanation": "Brief reasoning"
    }
    
    Note: 'components_activated' means you see the transition from red/inactive icons to green/active icons or you see the system working.
    """

    vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("science_category_entered"):
            vlm_score += 10
            feedback_parts.append("VLM: Science category found.")
            
        if parsed.get("water_cycle_activity_opened"):
            vlm_score += 20
            feedback_parts.append("VLM: Water Cycle opened.")
            
        if parsed.get("components_activated"):
            vlm_score += 15
            feedback_parts.append("VLM: Components activated.")
            
        if parsed.get("final_state_active"):
            vlm_score += 15
            feedback_parts.append("VLM: Cycle active.")
            
        feedback_parts.append(f"VLM Reason: {parsed.get('explanation', 'N/A')}")
    else:
        feedback_parts.append("VLM analysis failed.")

    score += vlm_score

    # Final Pass Logic
    # Must have at least opened the activity (VLM) and created the file evidence
    passed = score >= 70 and result.get("text_file_exists", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }