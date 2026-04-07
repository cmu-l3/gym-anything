#!/usr/bin/env python3
"""
Verifier for measure_area task in QField.

Task: Measure area between Paris, Brussels, Amsterdam.
Verification:
1. Primary: VLM Trajectory Analysis (Process + Final Result)
   - Checks if measurement tool was active
   - Checks if polygon was drawn in correct region
   - Checks if area value is displayed and reasonable
2. Secondary: Basic state checks (App running, time elapsed)
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Import VLM utilities provided by the framework
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback for local testing
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}
    def sample_trajectory_frames(traj, n=1): return []
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """
You are verifying a QField GIS task. The user was asked to measure the area of a triangle formed by Paris, Brussels, and Amsterdam using the Polygon Measurement Tool.

Review the sequence of screenshots (trajectory) and the final screen.

Criteria to check:
1. **Tool Usage**: Is the QField measurement tool (ruler icon/interface) active?
2. **Region**: Is the map showing Northwestern Europe (France/Belgium/Netherlands)? Look for city labels or geography.
3. **Geometry**: Is a triangular polygon drawn connecting three points roughly corresponding to Paris, Brussels, and Amsterdam?
4. **Result**: Is a numeric area measurement displayed on the screen?
   - Expected area is approx 7,000 - 9,000 km² (or 700,000 - 900,000 hectares).
   - Values between 5,000 and 15,000 km² are acceptable.
   - Ignore unit conversions if the magnitude is correct for the visible unit.

Respond in JSON:
{
    "tool_active": boolean,
    "correct_region": boolean,
    "triangle_polygon_visible": boolean,
    "measurement_value_visible": boolean,
    "measured_value_approx": "string or null",
    "score_reasoning": "string explanation"
}
"""

def verify_measure_area(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the measure_area task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function not available"}

    # 1. Retrieve JSON result from the environment
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: In Android envs, copy_from_env usually handles /sdcard paths
        copy_from_env("/sdcard/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution data"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    # 2. Basic Anti-Gaming Checks
    score = 0
    feedback_parts = []
    
    # Check 1: App was running at end (10 pts)
    if task_result.get("app_running", False):
        score += 10
        feedback_parts.append("QField is running")
    else:
        feedback_parts.append("QField was closed")

    # Check 2: Task duration (prevention of instant-completion) (5 pts)
    start_time = int(task_result.get("start_time", 0))
    end_time = int(task_result.get("end_time", 0))
    duration = end_time - start_time
    
    if duration > 10:
        score += 5
        feedback_parts.append(f"Duration ok ({duration}s)")
    else:
        feedback_parts.append(f"Task too short ({duration}s)")

    # 3. VLM Verification (85 pts total)
    # Use trajectory frames to see the workflow + final result
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    # Ensure we have images
    images_to_analyze = [img for img in frames + [final_shot] if img is not None]
    
    if not images_to_analyze:
        return {
            "passed": False, 
            "score": score, 
            "feedback": "No screenshots available for verification"
        }

    vlm_response = query_vlm(
        prompt=VLM_PROMPT,
        images=images_to_analyze
    )

    if not vlm_response.get("success"):
        return {
            "passed": False,
            "score": score,
            "feedback": f"VLM analysis failed: {vlm_response.get('error')}"
        }

    analysis = vlm_response.get("parsed", {})
    
    # Criterion 3.1: Correct Region (20 pts)
    if analysis.get("correct_region"):
        score += 20
        feedback_parts.append("Correct map region")
    
    # Criterion 3.2: Tool Active (20 pts)
    if analysis.get("tool_active"):
        score += 20
        feedback_parts.append("Measurement tool used")

    # Criterion 3.3: Polygon Visible (25 pts)
    if analysis.get("triangle_polygon_visible"):
        score += 25
        feedback_parts.append("Triangle polygon drawn")

    # Criterion 3.4: Value Visible (20 pts)
    if analysis.get("measurement_value_visible"):
        score += 20
        feedback_parts.append("Measurement result visible")

    feedback_parts.append(f"VLM Note: {analysis.get('score_reasoning', 'No reasoning')}")

    # Final Pass Determination
    # Must have > 50 points AND show the polygon + measurement
    passed = (score >= 60 and 
              analysis.get("triangle_polygon_visible") and 
              analysis.get("measurement_value_visible"))

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }