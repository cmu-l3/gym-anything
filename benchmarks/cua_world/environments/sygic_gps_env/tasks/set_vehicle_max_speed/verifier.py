#!/usr/bin/env python3
"""
Verifier for Sygic GPS task: set_vehicle_max_speed
"""

import json
import os
import sys
import tempfile
import logging
from typing import Dict, Any, List

# Import VLM utilities from the framework
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback for testing/dev environments
    def query_vlm(prompt, image=None, images=None):
        return {"success": False, "error": "VLM not available"}
    def sample_trajectory_frames(traj, n=5):
        return []
    def get_final_screenshot(traj):
        return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_set_vehicle_max_speed(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verifies that the vehicle max speed was set to 90 km/h.
    Uses VLM trajectory analysis to confirm navigation and value setting.
    """
    
    # 1. Setup and file retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # We don't rely heavily on the JSON result from Android since we can't easily grep specific UI elements
    # consistently across versions, but we'll try to get it for metadata.
    
    # 2. VLM Verification Strategy
    # We need to verify:
    # A) Agent went to Settings > Vehicle Profile
    # B) Agent interacted with Max Speed
    # C) Final state shows 90 km/h
    
    frames = sample_trajectory_frames(traj, n=6)
    final_screen = get_final_screenshot(traj)
    
    if not final_screen and not frames:
        return {"passed": False, "score": 0, "feedback": "No video evidence/screenshots available"}

    all_images = frames + ([final_screen] if final_screen else [])
    
    # Prompt for VLM Analysis
    prompt = """
    You are verifying a software test for Sygic GPS Navigation.
    The task was: "Configure the vehicle's maximum speed to exactly 90 km/h".
    
    Analyze the provided screenshots from the agent's session.
    
    Check for these specific milestones:
    1. Did the agent open the 'Settings' menu?
    2. Did the agent navigate to 'Vehicle profile' (or similar vehicle settings)?
    3. Did the agent open the 'Maximum speed' setting?
    4. Is the value '90 km/h' (or just '90') visible in the Maximum Speed field or summary?
    
    The final screenshot is the most important for verifying the final value.
    
    Respond in JSON format:
    {
        "settings_opened": true/false,
        "vehicle_profile_opened": true/false,
        "max_speed_interaction": true/false,
        "final_value_is_90": true/false,
        "observed_value": "string or null",
        "confidence": "high/medium/low"
    }
    """
    
    vlm_result = query_vlm(
        prompt=prompt,
        images=all_images
    )
    
    if not vlm_result.get('success'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Verification failed: {vlm_result.get('error')}"
        }
        
    parsed = vlm_result.get('parsed', {})
    logger.info(f"VLM Analysis: {parsed}")
    
    # 3. Scoring Calculation
    score = 0
    feedback_items = []
    
    # Criterion 1: Navigation (30 pts)
    if parsed.get('settings_opened'):
        score += 10
    if parsed.get('vehicle_profile_opened'):
        score += 20
        feedback_items.append("Navigated to Vehicle Profile")
    else:
        feedback_items.append("Failed to find Vehicle Profile settings")
        
    # Criterion 2: Interaction (20 pts)
    if parsed.get('max_speed_interaction'):
        score += 20
        feedback_items.append("Interacted with Max Speed setting")
        
    # Criterion 3: Value Verification (50 pts)
    final_value_correct = parsed.get('final_value_is_90', False)
    observed = parsed.get('observed_value', 'unknown')
    
    if final_value_correct:
        score += 50
        feedback_items.append("Max speed successfully set to 90 km/h")
    else:
        feedback_items.append(f"Incorrect final value (Observed: {observed}, Expected: 90)")
        
    # Pass threshold
    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_items)
    }