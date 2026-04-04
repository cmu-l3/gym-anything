#!/usr/bin/env python3
"""
Verifier for electricity_cost_calc task.

Verifies that the agent:
1. Navigated to the correct calculator in the app.
2. Entered the correct values (4200W, 8h, 30 days, $0.14).
3. Calculated the result ($141.12).
4. Saved a screenshot as requested.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Import VLM utilities from the environment framework
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback for local testing or if imports differ
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}
    def sample_trajectory_frames(traj, n=1): return []
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """
You are verifying an Electrical Engineering task. The user should be using the "Electrical Calculations" app to calculate electricity costs.

Task Parameters:
- Power: 4200 Watts (or 4.2 kW)
- Hours: 8 hours/day
- Days: 30 days
- Rate: 0.14 $/kWh
- Expected Result: Cost ~141.12, Energy ~1008 kWh

Please analyze the provided screenshot and determine:
1. Is the "Electricity Cost" (or "Energy Cost") calculator screen visible?
2. Are the input values correct (Power=4200, Hours=8, Days=30, Rate=0.14)?
3. Is the calculated result visible and approximately $141.12?

Output JSON format:
{
  "calculator_visible": boolean,
  "inputs_correct": boolean,
  "result_correct": boolean,
  "observed_cost": "string or number found",
  "observed_energy": "string or number found",
  "reasoning": "string"
}
"""

def verify_electricity_cost_calc(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Retrieve Programmatic Result
    programmatic_data = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            programmatic_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task state from device"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Programmatic Scoring (20 points)
    score = 0
    feedback = []

    # Check if app was left in foreground (10 pts)
    if programmatic_data.get("app_in_foreground", False):
        score += 10
        feedback.append("App is active.")
    else:
        feedback.append("App was not active at end.")

    # Check if user saved screenshot with valid timestamp (10 pts)
    if programmatic_data.get("user_screenshot_valid_timestamp", False):
        score += 10
        feedback.append("User screenshot saved correctly.")
    else:
        feedback.append("User screenshot missing or invalid timestamp.")

    # 3. VLM Verification (80 points)
    # We prioritize the final screenshot from the trajectory, 
    # but we can also check the user-saved one if we pulled it. 
    # For simplicity/robustness, we use the trajectory's final frame.
    
    final_frame = get_final_screenshot(traj)
    if final_frame is None:
         return {"passed": False, "score": score, "feedback": " | ".join(feedback) + " (No screenshot available for visual verification)"}

    vlm_response = query_vlm(
        image=final_frame,
        prompt=VLM_PROMPT
    )

    if not vlm_response.get("success"):
        feedback.append(f"VLM verification failed: {vlm_response.get('error')}")
    else:
        analysis = vlm_response.get("parsed", {})
        
        # VLM Criterion 1: Correct Screen (20 pts)
        if analysis.get("calculator_visible", False):
            score += 20
            feedback.append("Correct calculator screen.")
        else:
            feedback.append("Wrong screen visible.")

        # VLM Criterion 2: Inputs Correct (30 pts)
        if analysis.get("inputs_correct", False):
            score += 30
            feedback.append("Inputs matched parameters.")
        else:
            feedback.append("Incorrect input values.")

        # VLM Criterion 3: Result Correct (30 pts)
        if analysis.get("result_correct", False):
            score += 30
            feedback.append("Calculation result is correct.")
        else:
            obs_cost = analysis.get("observed_cost", "N/A")
            feedback.append(f"Incorrect result (saw {obs_cost}, expected ~141.12).")

    # 4. Final Verdict
    # Threshold: Need at least 70 points (implies inputs were entered and result was shown)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "programmatic": programmatic_data,
            "vlm_analysis": vlm_response.get("parsed", {})
        }
    }