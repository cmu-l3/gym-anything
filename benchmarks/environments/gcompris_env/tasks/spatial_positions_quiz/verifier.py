#!/usr/bin/env python3
"""
Verifier for Spatial Positions Quiz task.

Verification Strategy:
1. VLM Trajectory Analysis (90 points):
   - Confirms navigation to "Positions" activity.
   - Confirms interaction with spatial questions.
   - Confirms progression (different images/questions shown).
   - Confirms success feedback (green/smiley indicators).
2. Evidence Files (10 points):
   - Checks if agent saved the requested screenshots.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM utilities from framework
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames
except ImportError:
    # Mock for testing if library missing
    def query_vlm(prompt, images):
        return {"success": False, "error": "VLM library not found"}
    def sample_trajectory_frames(traj, n):
        return []

VLM_PROMPT = """
You are verifying an agent's performance in the GCompris educational software "Positions" activity.
The user must navigate to the activity and answer at least 5 spatial reasoning questions (e.g., identifying "On", "Under", "Behind").

Analyze the sequence of screenshots from the agent's session.

Check for the following:
1. **Activity Found**: Did the agent open an activity showing a cartoon image (like a cat, bird, or ball) relative to an object (box, house) with text buttons below it?
2. **Interaction**: Did the agent click on the answer buttons?
3. **Progression**: Do you see *different* question images appearing over time? (This indicates they are answering multiple questions).
4. **Success**: Do you see positive feedback (e.g., a smiley face, a flower, "Great!", or green highlighting) after they click?
5. **Count**: Does it look like they attempted at least 3-5 different questions?

Return your assessment in JSON format:
{
  "activity_found": true/false,
  "interaction_observed": true/false,
  "progression_observed": true/false,
  "success_feedback_observed": true/false,
  "estimated_rounds": <number>,
  "confidence": "low/medium/high",
  "reasoning": "Explain what you saw..."
}
"""

def verify_spatial_positions_quiz(traj, env_info, task_info):
    """
    Verify the spatial positions quiz task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load file-based results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            file_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Score File Evidence (10 points max)
    # 5 pts for question screenshot, 5 pts for success screenshot
    # Must be created *during* the task
    ev_q = file_result.get("evidence_question", {})
    ev_s = file_result.get("evidence_success", {})
    
    if ev_q.get("exists") and ev_q.get("created_in_task"):
        score += 5
        feedback_parts.append("Question screenshot saved")
    
    if ev_s.get("exists") and ev_s.get("created_in_task"):
        score += 5
        feedback_parts.append("Success screenshot saved")

    # 3. VLM Verification (90 points max)
    # We rely heavily on VLM because "completing 5 rounds" is visual
    frames = sample_trajectory_frames(traj, n=8)  # Sample enough frames to see progression
    
    if not frames:
        return {"passed": False, "score": score, "feedback": "No trajectory frames available for verification"}

    vlm_result = query_vlm(prompt=VLM_PROMPT, images=frames)
    
    if not vlm_result.get("success"):
        return {"passed": False, "score": score, "feedback": f"VLM verification failed: {vlm_result.get('error')}"}
    
    parsed = vlm_result.get("parsed", {})
    logger.info(f"VLM Analysis: {json.dumps(parsed, indent=2)}")

    # Scoring logic based on VLM
    if parsed.get("activity_found"):
        score += 20
        feedback_parts.append("Found correct activity")
        
        if parsed.get("interaction_observed"):
            score += 20
            feedback_parts.append("Interacted with UI")
            
            if parsed.get("success_feedback_observed"):
                score += 20
                feedback_parts.append("Success feedback seen")
            
            if parsed.get("progression_observed"):
                score += 30
                feedback_parts.append("Progression through multiple questions confirmed")
            else:
                feedback_parts.append("No progression seen (same question?)")
    else:
        feedback_parts.append("Did not find 'Positions' activity")

    # Pass Threshold
    # Must have found activity, interacted, and shown progression OR success
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": ", ".join(feedback_parts),
        "details": parsed
    }