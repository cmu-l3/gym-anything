#!/usr/bin/env python3
"""
Verifier for monitor_barn_solar_design task.

Uses a robust hybrid verification strategy:
1. File Verification: Checks that the required output files (.skp and .dae) exist, 
   were generated during the task, and meet minimum size thresholds.
2. VLM Trajectory Verification: Queries the VLM using several trajectory frames and 
   the final state to assess whether the agent successfully constructed a monitor barn
   shape and placed solar panels on BOTH the upper and lower roof levels.
"""

import os
import json
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are verifying if an agent successfully modeled an agricultural "Monitor Barn" and placed solar panels on multiple roof levels in SketchUp.

TASK REQUIREMENTS:
1. "Monitor Barn" Shape: A building structure with a raised, higher center roof section, accompanied by lower roof sections on the sides.
2. Upper Array: Solar panels (dark, flat, grid-like components) must be placed on the higher center roof.
3. Lower Array: Solar panels must also be placed on the lower side roof.

Review the provided screenshots of the 3D modeling process and determine:
1. Does the model feature a raised center roof and lower side roofs?
2. Are there solar panels placed on the higher roof?
3. Are there solar panels placed on the lower roof?

Respond in strict JSON format matching exactly this schema:
{
    "has_monitor_barn_shape": true/false,
    "panels_on_upper_roof": true/false,
    "panels_on_lower_roof": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of what is visible"
}
"""

def verify_monitor_barn_solar(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available."}
    if not query_vlm:
        return {"passed": False, "score": 0, "feedback": "System error: query_vlm not available."}

    metadata = task_info.get('metadata', {})
    min_skp_size = metadata.get('min_skp_size_bytes', 30000)
    min_dae_size = metadata.get('min_dae_size_bytes', 10000)

    feedback_parts = []
    score = 0
    max_score = 100

    # 1. READ EXPORTED RESULT JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Windows container path format
        copy_from_env("C:/Users/Docker/AppData/Local/Temp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Validate output files existence
    skp_exists = result.get('skp_exists', False)
    dae_exists = result.get('dae_exists', False)
    skp_size = result.get('skp_size_bytes', 0)
    dae_size = result.get('dae_size_bytes', 0)
    task_start = result.get('task_start', 0)
    dae_mtime = result.get('dae_mtime', 0)

    # 2. FILE VERIFICATION SCORING (20 points)
    if skp_exists:
        if skp_size > min_skp_size:
            score += 5
            feedback_parts.append("Valid SKP file saved")
        else:
            feedback_parts.append(f"SKP file too small ({skp_size} bytes)")
    else:
        feedback_parts.append("SKP file missing")

    if dae_exists:
        if dae_size > min_dae_size:
            score += 5
            feedback_parts.append("Valid DAE export found")
        else:
            feedback_parts.append(f"DAE file too small ({dae_size} bytes)")
    else:
        feedback_parts.append("DAE export missing")

    # Anti-gaming: Ensure file was modified during the task
    if dae_exists and dae_mtime > task_start:
        score += 10
        feedback_parts.append("Export completed during session")
    elif dae_exists:
        feedback_parts.append("Warning: DAE file was created before task start")

    # 3. VLM TRAJECTORY VERIFICATION (80 points)
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    images = frames + [final_frame] if final_frame else frames

    if not images:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + " | No visual evidence found"}

    vlm_result = query_vlm(prompt=VERIFICATION_PROMPT, images=images)
    
    vlm_passed = False
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        has_shape = parsed.get("has_monitor_barn_shape", False)
        upper_panels = parsed.get("panels_on_upper_roof", False)
        lower_panels = parsed.get("panels_on_lower_roof", False)
        
        if has_shape:
            score += 20
            feedback_parts.append("Monitor barn geometry identified")
        else:
            feedback_parts.append("Failed to create monitor barn geometry")
            
        if upper_panels:
            score += 30
            feedback_parts.append("Panels identified on upper roof")
        else:
            feedback_parts.append("Missing panels on upper roof")
            
        if lower_panels:
            score += 30
            feedback_parts.append("Panels identified on lower roof")
        else:
            feedback_parts.append("Missing panels on lower roof")
            
        vlm_passed = (has_shape and upper_panels and lower_panels)
    else:
        feedback_parts.append("VLM verification failed to process")

    # 4. FINAL VERIFICATION LOGIC
    key_criteria_met = (skp_exists and dae_exists and vlm_passed)
    passed = score >= 80 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }