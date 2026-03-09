#!/usr/bin/env python3
"""
Verifier for Pin Participant task.

This task relies primarily on VLM (Visual Language Model) verification because
Jitsi's internal state (Redux store) is difficult to access reliably from outside 
the browser sandbox without complex Selenium injection.

Verification Criteria:
1. Firefox is running (Agent active)
2. Epiphany is running (Guest active)
3. VLM Analysis of Final Screenshot:
   - Confirms "Stage View" (one large video tile dominant)
   - Confirms the large tile belongs to "Keynote Speaker"
   - Confirms "Pin" indicator/icon is visible (optional but good evidence)
"""

import json
import os
import sys
import tempfile
import logging
from datetime import datetime

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# VLM Interface (Mock/Stub for local testing, typically provided by environment)
# In the real evaluation environment, these are provided by the framework.
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames
except ImportError:
    # Fallback for testing
    def query_vlm(prompt, image=None, images=None):
        return {"success": False, "error": "VLM module not found"}
    def get_final_screenshot(traj):
        return None
    def sample_trajectory_frames(traj, n=1):
        return []

def verify_pin_participant(traj, env_info, task_info):
    """
    Verifies that the agent has pinned the 'Keynote Speaker'.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Basic Checks (Pre-requisites)
    score = 0
    feedback = []
    
    if result_data.get("firefox_running"):
        score += 10
        feedback.append("Agent browser active (+10)")
    else:
        feedback.append("Agent browser crashed or closed")
        
    if result_data.get("epiphany_running"):
        score += 10
        feedback.append("Guest participant active (+10)")
    else:
        feedback.append("Guest participant left (test invalid)")

    # 3. VLM Verification
    final_screenshot = get_final_screenshot(traj)
    if not final_screenshot:
        # Fallback to checking if we can get the one from export
        # (Though framework usually provides it in traj)
        return {"passed": False, "score": score, "feedback": "No evidence screenshot available"}

    # VLM Prompt Design
    prompt = """
    You are evaluating a screenshot of a Jitsi Meet video conference.
    
    The user is supposed to have PINNED the participant named 'Keynote Speaker'.
    
    Please analyze the image for the following:
    1. LAYOUT: Is the view in 'Stage View' (one large central video taking up most of the space) or 'Tile View' (grid of equal-sized videos)?
    2. CONTENT: Look at the LARGE central video. Does it display the name 'Keynote Speaker' (or initials like 'KS'/'K')?
    3. INDICATORS: Is there a blue 'pin' icon or any visual indicator on the 'Keynote Speaker' tile showing it is pinned?
    
    Respond in JSON format:
    {
        "layout_is_stage_view": true/false,
        "large_video_is_keynote_speaker": true/false,
        "pin_indicator_visible": true/false,
        "reasoning": "description of what you see"
    }
    """

    vlm_result = query_vlm(prompt=prompt, image=final_screenshot)
    
    if vlm_result.get("success"):
        analysis = vlm_result.get("parsed", {})
        logger.info(f"VLM Analysis: {analysis}")
        
        # Scoring Logic based on VLM
        if analysis.get("layout_is_stage_view", False):
            score += 30
            feedback.append("Correct layout (Stage View) (+30)")
            
            if analysis.get("large_video_is_keynote_speaker", False):
                score += 40
                feedback.append("Correct participant pinned (+40)")
            else:
                feedback.append("Wrong participant is main focus")
                
            if analysis.get("pin_indicator_visible", False):
                score += 10
                feedback.append("Pin indicator confirmed (+10)")
        else:
            feedback.append("Layout is Grid/Tile view (Participant not pinned)")
            
        final_reasoning = analysis.get("reasoning", "VLM analysis complete")
    else:
        feedback.append("VLM verification failed to process image")
        final_reasoning = "VLM Error"

    # 4. Final Assessment
    passed = score >= 80  # Requires Browser + Stage View + Correct Person
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "vlm_reasoning": final_reasoning,
            "raw_score": score
        }
    }