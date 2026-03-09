#!/usr/bin/env python3
"""
Verifier for scale_balance_activity.

Verification Strategy:
1. Primary: VLM Trajectory Analysis (80 points)
   - Did the agent navigate to the correct activity?
   - Is a balance scale visible?
   - Is there evidence of weights being moved?
   - Is there evidence of progression (multiple levels)?
2. Secondary: Programmatic Checks (20 points)
   - App running at end
   - Database/files modified (interaction evidence)
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt for Trajectory Analysis
TRAJECTORY_PROMPT = """You are analyzing screenshots of an agent using educational software (GCompris).
The task is to play the "Scales Board" (Balance) activity.

Look at the sequence of images and answer the following:

1. **Navigation**: Did the agent navigate from the main menu to an activity showing a balance scale?
2. **Activity Identification**: Is the "Scales Board" activity visible? (Look for a two-pan balance scale and draggable weights).
3. **Gameplay**: Is there evidence of the agent interacting with the activity (dragging weights onto the scale)?
4. **Progression**: Does the agent complete levels? Look for:
   - The scale becoming balanced (horizontal).
   - "Great" or success animations/messages.
   - The layout of weights changing (indicating a new level).
   - At least 3 different weight configurations attempted.

Score the attempt based on these criteria.

Respond in JSON format:
{
    "navigated_to_activity": true/false,
    "correct_activity_identified": true/false,
    "interaction_observed": true/false,
    "levels_completed_estimate": 0,
    "progression_observed": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what you see"
}
"""

def verify_scale_balance_activity(traj, env_info, task_info):
    """
    Verify the scale balance task using VLM and system state.
    """
    # 1. Setup helpers
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy function missing"}

    # 2. Load Programmatic Results
    task_result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution data"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Calculate Programmatic Score (20 pts)
    prog_score = 0
    feedback_parts = []
    
    if task_result.get("app_running", False):
        prog_score += 10
        feedback_parts.append("App kept running")
    else:
        feedback_parts.append("App crashed or closed")

    if task_result.get("db_modified", False):
        prog_score += 10
        feedback_parts.append("Data interaction detected")
    
    # 4. Perform VLM Verification (80 pts)
    vlm_score = 0
    frames = sample_trajectory_frames(traj, n=6) # Sample 6 frames to catch progression
    final_frame = get_final_screenshot(traj)
    
    # Add final frame to analysis if unique
    if final_frame:
        frames.append(final_frame)
    
    if not frames:
        return {"passed": False, "score": prog_score, "feedback": "No screenshots available for verification"}

    try:
        vlm_resp = query_vlm(
            images=frames,
            prompt=TRAJECTORY_PROMPT
        )
        
        if vlm_resp and vlm_resp.get("success"):
            analysis = vlm_resp.get("parsed", {})
            
            # Scoring logic based on VLM analysis
            if analysis.get("navigated_to_activity", False):
                vlm_score += 10
                feedback_parts.append("Navigated to activity")
                
            if analysis.get("correct_activity_identified", False):
                vlm_score += 20
                feedback_parts.append("Correct scales activity found")
                
            if analysis.get("interaction_observed", False):
                vlm_score += 20
                feedback_parts.append("gameplay interaction observed")
                
            if analysis.get("progression_observed", False):
                vlm_score += 30
                feedback_parts.append("Level progression observed")
                
            est_levels = analysis.get("levels_completed_estimate", 0)
            if isinstance(est_levels, int) and est_levels >= 3:
                feedback_parts.append(f"VLM estimated {est_levels} levels completed")
            elif analysis.get("progression_observed", False):
                # Fallback if specific count isn't parsed but progression is seen
                feedback_parts.append("Progression confirmed")
                
            feedback_parts.append(f"VLM Analysis: {analysis.get('reasoning', 'No details')}")
            
        else:
            feedback_parts.append("VLM verification failed to process images")
            
    except Exception as e:
        logger.error(f"VLM error: {e}")
        feedback_parts.append(f"VLM error: {str(e)}")

    # 5. Final Scoring
    total_score = prog_score + vlm_score
    passed = total_score >= 60 and "Correct scales activity found" in str(feedback_parts)

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback_parts)
    }