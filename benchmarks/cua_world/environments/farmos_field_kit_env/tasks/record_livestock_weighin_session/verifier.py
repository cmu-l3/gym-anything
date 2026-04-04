#!/usr/bin/env python3
"""
Verifier for record_livestock_weighin_session task.

Strategy:
1. VLM-based verification of the final state and trajectory.
2. Checks for correct Log Type, Date, Notes content, and Quantity.
3. Anti-gaming check via timestamps.
"""

import json
import os
import logging
import tempfile
import time
from typing import Dict, Any, List

# Simulated import for gym_anything VLM utils
# In a real environment, these would be available
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames
except ImportError:
    # Fallback/Mock for development environment
    def query_vlm(prompt, image=None, images=None):
        return {"success": False, "error": "VLM module not found"}
    def get_final_screenshot(traj):
        return None
    def sample_trajectory_frames(traj, n=1):
        return []

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_weighin_session(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the livestock weigh-in session log creation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_strings = metadata.get('required_strings', [])
    expected_date = metadata.get('expected_date', "2024-11-15")

    # 1. Retrieve Artifacts from Environment
    temp_dir = tempfile.mkdtemp()
    final_screenshot_path = os.path.join(temp_dir, "final_screenshot.png")
    timing_file_path = os.path.join(temp_dir, "task_timing.json")
    
    try:
        copy_from_env("/sdcard/final_screenshot.png", final_screenshot_path)
        copy_from_env("/sdcard/task_timing.json", timing_file_path)
        
        with open(timing_file_path, 'r') as f:
            timing_data = json.load(f)
            task_duration = int(timing_data.get("end", 0)) - int(timing_data.get("start", 0))
    except Exception as e:
        logger.warning(f"Artifact retrieval failed: {e}")
        task_duration = 0
        # If final screenshot missing, we rely solely on trajectory if available, else fail
    
    # 2. VLM Verification Strategy
    # We use trajectory frames to confirm steps were taken, and final screenshot for result.
    
    # Sample frames to see the editing process
    traj_frames = sample_trajectory_frames(traj, n=5)
    
    # Prepare VLM Prompt
    prompt = f"""
    You are evaluating an agent's performance in the farmOS Field Kit app.
    
    Goal: Create an 'Observation' log for a livestock weigh-in.
    Specific Requirements:
    - Log Type: Observation
    - Date: {expected_date} (Nov 15, 2024)
    - Notes must contain: "Monthly weigh-in", "Animal #12: 485 kg", "Animal #45: 520 kg"
    - Quantity: 6 head
    
    Analyze the provided screenshots (trajectory sequence and final state).
    
    Check for the following:
    1. Was a new log created?
    2. Is the Log Type set to 'Observation'?
    3. Is the Date set correctly to {expected_date}?
    4. Do the Notes contain the specific animal weights listed?
    5. Is the Quantity set to 6?
    6. Is the final state showing the saved log in the list?
    
    Provide a JSON response:
    {{
        "log_created": boolean,
        "type_is_observation": boolean,
        "date_is_correct": boolean,
        "notes_contain_weights": boolean,
        "quantity_is_correct": boolean,
        "saved_successfully": boolean,
        "confidence": float (0-1)
    }}
    """
    
    # If we have a local high-res final screenshot, prefer that for the last frame
    images_to_analyze = traj_frames
    if os.path.exists(final_screenshot_path):
        images_to_analyze.append(final_screenshot_path)
    elif len(traj_frames) > 0:
        # If no exported screenshot, reuse the last trajectory frame
        pass
    else:
        return {"passed": False, "score": 0, "feedback": "No visual evidence available (no trajectory or screenshot)."}

    vlm_result = query_vlm(prompt=prompt, images=images_to_analyze)
    
    if not vlm_result.get("success"):
        return {"passed": False, "score": 0, "feedback": f"VLM Verification failed: {vlm_result.get('error')}"}
    
    analysis = vlm_result.get("parsed", {})
    
    # 3. Scoring
    score = 0
    feedback = []
    
    # Criterion 1: Log Created (15 pts)
    if analysis.get("log_created"):
        score += 15
        feedback.append("Log creation initiated.")
    else:
        feedback.append("Failed to create log.")
        
    # Criterion 2: Log Type Correct (15 pts)
    if analysis.get("type_is_observation"):
        score += 15
        feedback.append("Log type 'Observation' selected.")
    else:
        feedback.append("Incorrect log type (expected Observation).")
        
    # Criterion 3: Date Correct (20 pts)
    if analysis.get("date_is_correct"):
        score += 20
        feedback.append(f"Date set to {expected_date}.")
    else:
        feedback.append("Incorrect date.")
        
    # Criterion 4: Notes Content (25 pts)
    if analysis.get("notes_contain_weights"):
        score += 25
        feedback.append("Notes contain required weight data.")
    else:
        feedback.append("Notes missing required weight data.")
        
    # Criterion 5: Quantity (15 pts)
    if analysis.get("quantity_is_correct"):
        score += 15
        feedback.append("Quantity set to 6.")
    else:
        feedback.append("Incorrect quantity.")
        
    # Criterion 6: Saved/Final State (10 pts)
    if analysis.get("saved_successfully"):
        score += 10
        feedback.append("Log saved successfully.")
    else:
        feedback.append("Log not saved or not visible in final list.")
    
    # Anti-gaming check
    if task_duration < 5: # It takes time to type notes
        score = 0
        feedback = ["Task duration too short, likely no work done."]

    passed = score >= 65 and analysis.get("log_created") and analysis.get("type_is_observation")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }