#!/usr/bin/env python3
"""
Verifier for start_route_simulation task.

Verification Strategy:
1. Programmatic: Check if Sygic is in foreground and if task duration is reasonable.
2. VLM (Primary): Analyze trajectory to verify the workflow:
   - Search for "Golden Gate Bridge"
   - Plan route
   - Activation of simulation
   - Final state showing active navigation/simulation
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Import VLM utilities from the environment framework
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_start_route_simulation(traj, env_info, task_info):
    """
    Verify that the user planned a route to Golden Gate Bridge and started simulation.
    """
    # 1. Setup copy mechanism
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env not available"}

    # 2. Retrieve Programmatic Results
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    programmatic_data = {}
    
    try:
        # File is at /sdcard/task_result.json in the android env
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            programmatic_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load programmatic results: {e}")
        # Continue, as VLM is primary for this visual task
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 3. Analyze Programmatic Signals (20 points max)
    score = 0
    feedback = []
    
    # Check 1: App Foreground (10 pts)
    if programmatic_data.get("app_in_foreground", False):
        score += 10
        feedback.append("Sygic app is active.")
    else:
        feedback.append("Sygic app was not in foreground at the end.")

    # Check 2: Activity Heuristics (10 pts)
    # Activities containing 'Drive', 'Navi', 'Map' usually indicate map/nav state
    activity_name = programmatic_data.get("resumed_activity", "")
    if any(x in activity_name for x in ["Drive", "Navi", "Map", "Route"]):
        score += 10
        feedback.append("Activity state indicates navigation/map view.")

    # 4. VLM Verification (80 points max)
    # We need to verify the specific destination and the simulation state
    
    frames = sample_trajectory_frames(traj, n=6)
    final_screen = get_final_screenshot(traj)
    
    # Combined VLM prompt
    prompt = """
    You are verifying an agent's interaction with Sygic GPS Navigation.
    The goal is: Plan a route to "Golden Gate Bridge" and start the "Route Simulation" (demo).
    
    Review the provided screenshot trajectory and final state.
    
    Check for the following steps:
    1. Search: Did the agent search for "Golden Gate Bridge"?
    2. Selection: Did they select the correct result?
    3. Route Plan: Did a route overview appear?
    4. Simulation: Is the final state showing an ACTIVE navigation simulation? 
       (Look for a moving map perspective, turn-by-turn arrows, speed/distance indicators, or 'Demo' text).
       
    IMPORTANT: Distinguish between a static "Route Preview" map and an active "Simulation/Drive" view.
    
    Return JSON:
    {
        "searched_correct_destination": boolean,
        "route_planned": boolean,
        "simulation_active": boolean,
        "final_screen_description": "string",
        "confidence": "high/medium/low"
    }
    """
    
    vlm_result = query_vlm(
        images=frames + [final_screen],
        prompt=prompt
    )
    
    if not vlm_result.get("success", False):
        return {
            "passed": False, 
            "score": score, 
            "feedback": f"VLM Verification failed: {vlm_result.get('error')}"
        }

    parsed = vlm_result.get("parsed", {})
    
    # VLM Scoring
    if parsed.get("searched_correct_destination", False):
        score += 20
        feedback.append("Correct destination searched.")
    else:
        feedback.append("Could not confirm search for Golden Gate Bridge.")
        
    if parsed.get("route_planned", False):
        score += 20
        feedback.append("Route planning verified.")
    else:
        feedback.append("Route was not successfully planned.")
        
    if parsed.get("simulation_active", False):
        score += 40
        feedback.append("Route simulation is active.")
    else:
        feedback.append("Route simulation NOT detected in final state.")

    # Final Pass Logic
    # Must have simulation active OR (route planned + correct destination) for partial pass
    # But for full pass, simulation is required.
    
    passed = score >= 80 and parsed.get("simulation_active", False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": parsed
    }