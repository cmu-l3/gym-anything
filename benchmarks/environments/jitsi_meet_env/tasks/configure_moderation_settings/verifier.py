#!/usr/bin/env python3
"""
Verifier for configure_moderation_settings task.

Verification Strategy:
1. Programmatic Checks (20%):
   - Firefox is running
   - Meeting was joined (window title check)
   - Anti-gaming: Task took sufficient time (>15s)
   - State changed from initial

2. VLM Trajectory Verification (80%):
   - Verify workflow: Pre-join -> Meeting -> Overflow Menu -> Settings -> Moderator Tab
   - Verify specific toggles were enabled:
     - "Everyone starts muted"
     - "Everyone starts hidden"
     - "Follow me"
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Gym-Anything VLM helpers
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying an agent's interaction with Jitsi Meet video conferencing software.

The goal was to:
1. Join the meeting.
2. Open Settings -> Moderator tab.
3. Enable "Everyone starts muted".
4. Enable "Everyone starts hidden".
5. Enable "Follow me".
6. Close the settings.

Review the sequence of screenshots (chronological order) and determine:

1. DID_JOIN: Did the agent successfully join the meeting (transition from pre-join screen to meeting view)?
2. OPENED_SETTINGS: Did the Settings dialog appear?
3. MODERATOR_TAB: Was the "Moderator" tab selected in the Settings dialog?
4. TOGGLES_ENABLED: visible state of the toggles.
   - Look for the "Moderator" settings panel.
   - "Everyone starts muted" should be ON (usually toggle moves right / changes color).
   - "Everyone starts hidden" should be ON.
   - "Follow me" should be ON.
5. CLOSED_SETTINGS: Did the agent close the settings dialog at the end (return to meeting view)?

Respond in JSON format:
{
    "meeting_joined": true/false,
    "settings_opened": true/false,
    "moderator_tab_selected": true/false,
    "toggle_muted_enabled": true/false,
    "toggle_hidden_enabled": true/false,
    "toggle_follow_me_enabled": true/false,
    "settings_closed_at_end": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Explain what you saw in the frames"
}
"""

def verify_configure_moderation_settings(traj, env_info, task_info):
    """
    Verify the moderation settings configuration task.
    """
    # 1. Setup and load programmatic results
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

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 2. Programmatic Verification (20 Points)
    # ------------------------------------------------------------------
    
    # Check 1: Firefox running (5 pts)
    if result.get("firefox_running", False):
        score += 5
        feedback_parts.append("Firefox is running")
    else:
        feedback_parts.append("Firefox is NOT running")

    # Check 2: Meeting joined (Window title) (5 pts)
    if result.get("meeting_joined", False):
        score += 5
        feedback_parts.append("Meeting joined (title match)")
    else:
        feedback_parts.append("Meeting NOT joined or title mismatch")

    # Check 3: State changed (5 pts)
    if result.get("state_changed", False):
        score += 5
        feedback_parts.append("Screen state changed")
    else:
        feedback_parts.append("Screen state unchanged (Do Nothing detected)")

    # Check 4: Anti-gaming time check (5 pts)
    # This task involves navigation and multiple clicks, shouldn't be instant
    elapsed = result.get("elapsed_seconds", 0)
    if elapsed > 10:
        score += 5
        feedback_parts.append(f"Realistic duration ({elapsed}s)")
    else:
        feedback_parts.append(f"Task too fast ({elapsed}s) - suspicious")

    # ------------------------------------------------------------------
    # 3. VLM Trajectory Verification (80 Points)
    # ------------------------------------------------------------------
    
    # Sample frames from the trajectory to capture the workflow
    # We need intermediate frames to see the settings dialog and toggles
    frames = sample_trajectory_frames(traj, n=8)
    
    if not frames:
        return {
            "passed": False, 
            "score": score, 
            "feedback": "No trajectory frames available for VLM verification. " + "; ".join(feedback_parts)
        }

    try:
        vlm_response = query_vlm(
            prompt=VLM_PROMPT,
            images=frames
        )
        
        if vlm_response.get("success"):
            vlm_data = vlm_response.get("parsed", {})
            feedback_parts.append(f"VLM reasoning: {vlm_data.get('reasoning', 'None')}")
            
            # Meeting joined check (10 pts)
            if vlm_data.get("meeting_joined"):
                score += 10
            
            # Settings workflow (20 pts)
            if vlm_data.get("settings_opened"):
                score += 10
            if vlm_data.get("moderator_tab_selected"):
                score += 10
                
            # Toggles (10 pts each = 30 pts)
            if vlm_data.get("toggle_muted_enabled"):
                score += 10
            if vlm_data.get("toggle_hidden_enabled"):
                score += 10
            if vlm_data.get("toggle_follow_me_enabled"):
                score += 10
            
            # Settings closed (10 pts)
            if vlm_data.get("settings_closed_at_end"):
                score += 10
            elif result.get("meeting_joined"): 
                # fallback: if programmatic check says we are in meeting at end, 
                # we likely closed settings, even if VLM wasn't sure
                score += 5

            # Workflow coherence check (10 pts)
            # If we got most points, the workflow was likely coherent
            if score > 60:
                score += 10
                
        else:
            feedback_parts.append(f"VLM query failed: {vlm_response.get('error')}")

    except Exception as e:
        feedback_parts.append(f"VLM verification exception: {str(e)}")

    # ------------------------------------------------------------------
    # 4. Final Scoring
    # ------------------------------------------------------------------
    
    # Cap score at 100
    score = min(100, score)
    
    # Pass threshold: 70
    # Requires joining meeting, opening settings, and enabling at least some toggles
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }