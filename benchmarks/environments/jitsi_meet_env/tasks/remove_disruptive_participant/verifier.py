#!/usr/bin/env python3
"""
Verifier for remove_disruptive_participant task.

Verification Strategy:
1. Anti-Gaming Check (Programmatic): 
   - Ensure the "DisruptiveUser" browser process (Epiphany) is still running.
   - If the agent killed the process via terminal, they fail.
   - A kicked user in Jitsi stays in the browser (redirected to "You have been kicked").

2. Success Verification (VLM):
   - Analyze final screenshot to confirm "DisruptiveUser" is GONE from the meeting.
   - Analyze trajectory to confirm the agent used the UI (Kick/Remove button).
   - Confirm agent is still in the meeting (participant count = 1).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_remove_disruptive_participant(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Programmatic Results
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

    score = 0
    feedback_parts = []
    
    # Check 1: Process Integrity (Anti-gaming) (20 pts)
    # The disruptive user's browser should still be open, just kicked from the meeting.
    if result.get("disruptive_process_running", False):
        score += 20
        feedback_parts.append("Background process integrity maintained (20/20)")
    else:
        feedback_parts.append("FAIL: DisruptiveUser process was killed (agent should use Jitsi UI)")
        return {"passed": False, "score": 0, "feedback": "Failed: Do not kill the background process. Use the Jitsi interface."}

    # Check 2: Agent Survival (20 pts)
    if result.get("agent_running", False):
        score += 20
        feedback_parts.append("Agent remains in meeting (20/20)")
    else:
        feedback_parts.append("Agent browser closed unexpectedly")

    # Check 3: VLM Verification of Meeting State (60 pts)
    final_screenshot = get_final_screenshot(traj)
    trajectory_frames = sample_trajectory_frames(traj, n=4)
    
    if not final_screenshot:
        return {"passed": False, "score": score, "feedback": "No screenshots available"}

    # VLM Prompt
    prompt = """
    You are verifying a Jitsi Meet moderation task.
    The agent (Moderator) was supposed to remove a participant named 'DisruptiveUser'.
    
    Analyze the FINAL screenshot and the trajectory.
    
    Questions:
    1. Is the agent currently in an active meeting? (Look for meeting toolbar, filmstrip)
    2. How many participants are visible in the FINAL screenshot? (Should be 1, just the agent)
    3. Is 'DisruptiveUser' visible in the FINAL screenshot? (Should be NO)
    4. Did you see a 'Kick', 'Remove', or context menu action in the trajectory frames?
    
    Respond in JSON:
    {
        "in_meeting": boolean,
        "participant_count": number,
        "disruptive_user_visible": boolean,
        "kick_action_observed": boolean,
        "reasoning": "string"
    }
    """
    
    vlm_response = query_vlm(images=trajectory_frames + [final_screenshot], prompt=prompt)
    
    if vlm_response and vlm_response.get("success"):
        parsed = vlm_response.get("parsed", {})
        
        # Criteria A: Disruptive User Gone (30 pts)
        if not parsed.get("disruptive_user_visible", True): # Should be False
            score += 30
            feedback_parts.append("DisruptiveUser successfully removed (30/30)")
        else:
            feedback_parts.append("DisruptiveUser still visible")

        # Criteria B: Participant Count is 1 (20 pts)
        # Note: Sometimes self-view makes it 1 tile.
        count = parsed.get("participant_count", 2)
        if count == 1:
            score += 20
            feedback_parts.append("Correct participant count: 1 (20/20)")
        else:
            feedback_parts.append(f"Incorrect participant count: {count}")

        # Criteria C: Kick Action Observed (10 pts)
        if parsed.get("kick_action_observed", False):
            score += 10
            feedback_parts.append("Kick action observed in trajectory (10/10)")
        else:
            feedback_parts.append("Kick action not clearly visible in trajectory")
            
    else:
        feedback_parts.append("VLM verification failed")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }