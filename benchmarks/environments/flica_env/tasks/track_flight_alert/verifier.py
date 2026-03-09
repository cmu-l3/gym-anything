#!/usr/bin/env python3
"""
Verifier for track_flight_alert@1 task.
Evaluates if the agent successfully searched for flight DL400 and enabled tracking.

SCORING CRITERIA:
1. Programmatic Signals (40 pts):
   - App running (5 pts)
   - UI State Changed (10 pts)
   - Flight-related text found (10 pts)
   - "DL400" specific text found (15 pts)

2. VLM Trajectory Verification (60 pts):
   - Did agent find the search feature? (20 pts)
   - Did agent enter DL400? (20 pts)
   - Did agent view results/activate tracking? (20 pts)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_track_flight_alert(traj, env_info, task_info):
    """
    Verify flight tracking task using hybrid programmatic + VLM approach.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Programmatic Scoring (40 pts max)
    score = 0
    feedback_parts = []
    
    # Check 1: App Running (5 pts)
    if result.get('app_running', False):
        score += 5
    else:
        feedback_parts.append("App was closed/crashed")

    # Check 2: UI Changed (10 pts) - Anti-gaming
    if result.get('ui_changed', False):
        score += 10
    else:
        feedback_parts.append("UI did not change (did nothing)")

    # Check 3: Flight Context (10 pts)
    if result.get('flight_text_found', False):
        score += 10
        feedback_parts.append("Flight context found in UI")
    
    # Check 4: Specific Flight Number (15 pts)
    if result.get('dl400_found', False):
        score += 15
        feedback_parts.append("DL400 found in final UI")
    else:
        feedback_parts.append("DL400 NOT found in final UI")

    # 3. VLM Trajectory Verification (60 pts max)
    # Use trajectory frames to verify workflow steps that static analysis misses
    frames = sample_trajectory_frames(traj, n=6)
    
    vlm_prompt = """
    You are verifying an agent's attempt to track a flight in the Flight Crew View app.
    Goal: Search for flight 'DL400' and add it to tracking/alerts.
    
    Analyze the screenshots sequence and answer these questions:
    1. Did the agent navigate away from the initial friend list to a search or flight screen?
    2. Is 'DL400' (or Delta 400) visible in any search field or result?
    3. Did the agent tap a 'Track', 'Add', 'Follow' button or toggle a switch for this flight?
    4. Does the final state show the flight details or a confirmation?
    
    Respond in JSON:
    {
        "found_search_feature": boolean,
        "entered_flight_number": boolean,
        "attempted_tracking": boolean,
        "confidence": "high/medium/low",
        "reasoning": "string"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        # VLM Criterion A: Navigation (20 pts)
        if parsed.get("found_search_feature", False):
            score += 20
            feedback_parts.append("VLM: Found search feature")
        
        # VLM Criterion B: Data Entry (20 pts)
        if parsed.get("entered_flight_number", False):
            score += 20
            feedback_parts.append("VLM: Entered DL400")
            
        # VLM Criterion C: Action (20 pts)
        if parsed.get("attempted_tracking", False):
            score += 20
            feedback_parts.append("VLM: Attempted to track")
        elif score >= 80: # If everything else is perfect but tracking button wasn't clear
            # Check if programmatic signal for tracking exists as fallback
            if result.get('track_keyword_found', False):
                score += 15
                feedback_parts.append("Text: Tracking keyword found")
                
        reasoning = parsed.get("reasoning", "No reasoning provided")
        feedback_parts.append(f"VLM Analysis: {reasoning}")
    else:
        feedback_parts.append("VLM verification failed")

    # 4. Final Determination
    # Pass threshold: 55 points (Must find feature + enter number + basics)
    passed = score >= 55
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }