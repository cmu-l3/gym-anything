#!/usr/bin/env python3
"""
Verifier for find_all_traffic_light_colors_midostaurin task.

Verification Strategy:
1. Anti-gaming: Check task duration and app visibility from result JSON.
2. VLM Trajectory Analysis:
   - Sample frames from the agent's interaction.
   - Verify 'Midostaurin' was the selected cancer drug.
   - Identify which of the 5 traffic light colors (Red, Orange, Yellow, Green, Grey)
     were visited/exposed during the session.
"""

import json
import tempfile
import os
import logging
import time
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_traffic_light_colors(traj, env_info, task_info):
    """
    Verify that the agent found examples of all 5 traffic light colors for Midostaurin.
    """
    # 1. Setup and Basic Checks
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Anti-gaming: Check duration
    duration = result.get("duration_seconds", 0)
    if duration < 20:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Task completed too quickly ({duration}s). Impossible to verify 5 interactions in this time."
        }

    # 2. VLM Trajectory Verification
    # We need to see the HISTORY of what the agent looked at, not just the final screen.
    frames = sample_trajectory_frames(traj, n=12) # Sample heavily to catch the different colors
    
    prompt = """
    You are verifying an agent's interaction with the 'Liverpool Cancer iChart' app.
    The goal was to check the drug 'Midostaurin' and find one example co-medication for EACH of the 5 traffic light colors:
    - RED (Do Not Coadminister)
    - ORANGE (Potential Interaction)
    - YELLOW (Potential Weak Interaction)
    - GREEN (No Interaction Expected)
    - GREY (No Clear Data)

    Review the sequence of screenshots and determine:
    1. Was the cancer drug 'Midostaurin' selected?
    2. Which traffic light colors were clearly viewed (either by tapping into the detail view or pausing on the list entry)?
    3. Did the agent scroll systematically to find these?

    Respond in JSON format:
    {
        "drug_selected": "Midostaurin" or "Other" or "None",
        "colors_found": ["Red", "Green", ...], 
        "systematic_scrolling": true/false,
        "confidence": "low/medium/high",
        "reasoning": "brief explanation"
    }
    """

    vlm_response = query_vlm(images=frames, prompt=prompt)
    
    if not vlm_response.get("success"):
        return {"passed": False, "score": 0, "feedback": "VLM verification failed"}

    analysis = vlm_response.get("parsed", {})
    logger.info(f"VLM Analysis: {json.dumps(analysis, indent=2)}")

    # 3. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criterion 1: Correct Drug (10 pts)
    drug = analysis.get("drug_selected", "None")
    if "midostaurin" in str(drug).lower():
        score += 10
        feedback_parts.append("Correct drug (Midostaurin) selected.")
    else:
        feedback_parts.append(f"Wrong drug selected: {drug}.")

    # Criterion 2: Colors Found (15 pts each, max 75)
    found_colors = [c.lower() for c in analysis.get("colors_found", [])]
    required_colors = ["red", "orange", "yellow", "green", "grey"]
    
    colors_score = 0
    found_list = []
    for color in required_colors:
        # Check for direct match or variations (gray/grey)
        if color in found_colors or (color == "grey" and "gray" in found_colors):
            colors_score += 15
            found_list.append(color.title())
    
    score += colors_score
    feedback_parts.append(f"Colors found: {', '.join(found_list)} ({len(found_list)}/5).")

    # Criterion 3: Systematic Process (15 pts)
    # Awarded if at least 3 colors were found OR VLM explicitly noted systematic scrolling
    if len(found_list) >= 3 or analysis.get("systematic_scrolling", False):
        score += 15
        feedback_parts.append("Systematic exploration verified.")

    # Final Check
    passed = (score >= 60) and ("midostaurin" in str(drug).lower())
    
    return {
        "passed": passed,
        "score": min(score, 100), # Cap at 100
        "feedback": " ".join(feedback_parts),
        "details": analysis
    }