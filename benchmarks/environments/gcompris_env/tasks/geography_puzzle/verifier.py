#!/usr/bin/env python3
"""
Verifier for Geography Puzzle Task (geography_puzzle@1).

Verification Strategy:
1. Programmatic: Check if GCompris is running and if the agent saved a screenshot.
2. VLM (Trajectory): Verify navigation to Discovery -> Geography -> South America.
3. VLM (Final State): Verify at least 4 countries are placed on the map.
"""

import json
import os
import sys
import logging
import tempfile
from typing import Dict, Any

# Adjust path to import vlm_utils from gym_anything
# In the container/environment, these are typically available or we use the framework provided ones.
# For this template, we assume standard framework availability.

try:
    from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames
except ImportError:
    # Fallback or mock for testing if library not present
    def query_vlm(**kwargs): return {"success": False, "error": "VLM lib not found"}
    def get_final_screenshot(traj): return None
    def sample_trajectory_frames(traj, n): return []

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_geography_puzzle(traj, env_info, task_info):
    """
    Verify the agent navigated to the geography puzzle and placed countries.
    """
    # 1. Setup and Load Programmatic Results
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    max_score = 100

    # Load JSON result from container
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

    # 2. Programmatic Scoring (15 points max)
    
    # Check if app is running (5 pts)
    if result.get("app_running", False):
        score += 5
        feedback_parts.append("GCompris is running (+5)")
    else:
        feedback_parts.append("GCompris was closed (+0)")

    # Check if agent saved valid screenshot (10 pts)
    if result.get("evidence_valid", False):
        score += 10
        feedback_parts.append("Agent saved valid screenshot (+10)")
    elif result.get("evidence_exists", False):
        score += 5
        feedback_parts.append("Agent saved screenshot but validation failed (timestamp/size) (+5)")
    else:
        feedback_parts.append("No screenshot saved by agent (+0)")

    # 3. VLM Verification (85 points max)
    
    # Get images
    final_screenshot = get_final_screenshot(traj)
    traj_frames = sample_trajectory_frames(traj, n=4)
    
    if not final_screenshot:
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts) + " | No screenshots available for verification"
        }

    # PROMPT 1: Verify Navigation (Trajectory)
    nav_prompt = """
    You are analyzing screenshots of a user navigating the GCompris educational software.
    
    The user needs to:
    1. Start at the Main Menu.
    2. Click the 'Discovery' category (usually a globe, magnifying glass, or computer icon).
    3. Click the 'Geography' or 'Place the countries' activity (map icon).
    4. Select 'South America'.
    
    Look at these sequential frames. Do you see evidence of this navigation flow?
    Does the user reach a map of South America?
    """
    
    nav_result = query_vlm(
        images=traj_frames, 
        prompt=nav_prompt + "\nRespond in JSON: {'navigated_correctly': bool, 'reached_map': bool, 'confidence': float}"
    )
    
    nav_data = nav_result.get("parsed", {}) if nav_result.get("success") else {}
    
    if nav_data.get("navigated_correctly", False):
        score += 15
        feedback_parts.append("Navigation flow verified (+15)")
    
    if nav_data.get("reached_map", False):
        score += 20
        feedback_parts.append("Geography activity reached (+20)")

    # PROMPT 2: Verify Final State (Map Completion)
    # We check the final screenshot (either system captured or agent captured)
    # Agent captured is preferred if valid, otherwise system final
    
    map_prompt = """
    Analyze this screenshot of the GCompris Geography/Map activity.
    
    Goal: The user should have placed countries onto the South America map.
    
    1. Is the South America map visible?
    2. Are there countries 'placed' on the map? (Placed countries usually appear colored/filled-in within the map outline, while unplaced ones are loose or the slots are empty/grey).
    3. Count approximately how many countries appear to be correctly placed/filled in.
    
    Required: At least 4 countries placed.
    
    Respond in JSON:
    {
        "map_visible": bool,
        "countries_placed_count": int (estimate),
        "at_least_4_placed": bool,
        "explanation": "string"
    }
    """
    
    map_result = query_vlm(
        image=final_screenshot,
        prompt=map_prompt
    )
    
    map_data = map_result.get("parsed", {}) if map_result.get("success") else {}
    
    if map_data.get("map_visible", False):
        # Only award if not already awarded by trajectory check, or verify consistency
        # We'll treat this as confirming the final state
        score += 15
        feedback_parts.append("South America map confirmed in final state (+15)")
        
    if map_data.get("at_least_4_placed", False):
        score += 35
        feedback_parts.append("At least 4 countries placed (+35)")
    elif map_data.get("countries_placed_count", 0) >= 1:
        score += 15
        feedback_parts.append("Some countries placed, but fewer than 4 (+15)")
        
    # Calculate Pass/Fail
    # Pass requires: App running + Reached Map + At least 1 country placed
    # Or strict threshold: Score >= 50
    passed = score >= 50 and map_data.get("map_visible", False) and (map_data.get("countries_placed_count", 0) >= 1)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "nav_analysis": nav_data,
            "map_analysis": map_data
        }
    }