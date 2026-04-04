#!/usr/bin/env python3
"""
Verifier for RC Time Constant calculation task.

Verification Strategy:
1. Check if the app was running in the foreground at the end (anti-gaming).
2. Use VLM to analyze the final state and trajectory:
   - Verify the "RC Time Constant" calculator is active.
   - Verify inputs: R = 47 kΩ, C = 100 μF.
   - Verify output: Time Constant ≈ 4.7 s.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Import VLM utilities from the framework
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rc_time_constant(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the agent correctly calculated the RC time constant.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON from device
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution data"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Extract Basic Signals
    app_running = result_data.get("app_running", False)
    
    if not app_running:
        return {
            "passed": False, 
            "score": 10, 
            "feedback": "The Electrical Calculations app was not open at the end of the task."
        }

    # 3. VLM Verification
    # We use trajectory frames to ensure the agent actually performed the actions
    # and didn't just stumble upon a static image (unlikely in Android, but good practice).
    frames = sample_trajectory_frames(traj, n=4)
    final_screenshot = get_final_screenshot(traj)
    
    if not final_screenshot:
        return {"passed": False, "score": 0, "feedback": "No screenshots available for verification."}

    # Construct VLM Prompt
    prompt = """
    You are an expert electrical engineering teaching assistant verifying a student's work on an Android app.
    
    The Task:
    1. Open 'Electrical Calculations' app.
    2. Go to 'RC Time Constant' calculator.
    3. Input Resistance (R) = 47 kΩ (or 47000 Ω).
    4. Input Capacitance (C) = 100 μF (or 0.0001 F).
    5. Calculate and show the Time Constant result (should be ~4.7 seconds).

    Review the final screenshot and the user's activity history.
    
    Check for the following criteria:
    1. **Correct Calculator**: Is the "RC Time Constant" (or similar) calculator visible?
    2. **Correct Inputs**: 
       - Resistance is 47 kΩ (or 47000).
       - Capacitance is 100 μF.
    3. **Correct Result**: Is the result displayed as approximately "4.7 s" (or 4700 ms)?
    
    Output JSON:
    {
        "calculator_visible": true/false,
        "inputs_correct": true/false,
        "result_correct": true/false,
        "observed_result": "string value seen",
        "reasoning": "explanation"
    }
    """
    
    # Send to VLM
    vlm_response = query_vlm(
        images=frames + [final_screenshot],
        prompt=prompt
    )
    
    if not vlm_response.get("success"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Verification failed due to VLM error: {vlm_response.get('error')}"
        }
    
    analysis = vlm_response.get("parsed", {})
    
    # 4. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criterion 1: App Running (Already checked)
    score += 10
    feedback_parts.append("App was running.")
    
    # Criterion 2: Correct Calculator (30 pts)
    if analysis.get("calculator_visible"):
        score += 30
        feedback_parts.append("Correct RC Time Constant calculator found.")
    else:
        feedback_parts.append("Could not confirm correct calculator was open.")

    # Criterion 3: Inputs Correct (30 pts)
    if analysis.get("inputs_correct"):
        score += 30
        feedback_parts.append("Input values (47kΩ, 100μF) appear correct.")
    else:
        feedback_parts.append("Input values incorrect or not visible.")

    # Criterion 4: Result Correct (30 pts)
    if analysis.get("result_correct"):
        score += 30
        feedback_parts.append(f"Result verified as correct (~4.7s). Observed: {analysis.get('observed_result', 'N/A')}")
    else:
        feedback_parts.append(f"Result incorrect. Observed: {analysis.get('observed_result', 'N/A')}")

    passed = score >= 90  # High threshold because exact numbers are required
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts),
        "details": analysis
    }