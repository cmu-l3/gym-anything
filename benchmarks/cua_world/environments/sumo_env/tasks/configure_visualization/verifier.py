#!/usr/bin/env python3
"""
Verifier for configure_visualization task.

Uses a combination of file/state programmatic checks and VLM-based trajectory analysis
to ensure the visualization was properly configured and the simulation ran.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def build_vlm_prompt():
    return """Examine these trajectory frames and the final screenshot of a SUMO-GUI session.

Task: The agent must configure edge/street coloring to "by speed" and run the simulation to let traffic build up.

Please check for the following:
1. "speed_coloring_active": Are the roads/edges colored in a gradient (e.g., green, yellow, orange, red) indicating traffic speed, rather than the default uniform gray/black?
2. "simulation_progressed": Can you see vehicles (small colored rectangles/triangles) actively distributed on the road network, indicating the simulation has been run?
3. "settings_dialog_used": Did the agent open the Visualization Settings dialog during the trajectory?

Respond in JSON format:
{
    "speed_coloring_active": true/false,
    "simulation_progressed": true/false,
    "settings_dialog_used": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what visual evidence supports your conclusions."
}
"""

def verify_configure_visualization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available."}

    # Retrieve expected metadata
    metadata = task_info.get('metadata', {})
    min_time_step = metadata.get('min_time_step', 500)

    # 1. Read JSON result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 2. Score Programmatic File Criteria
    
    # Screenshot Checks (20 points total)
    if result.get("screenshot_exists"):
        if result.get("screenshot_valid") and result.get("screenshot_size_bytes", 0) > 10000:
            score += 20
            feedback_parts.append("Valid screenshot saved")
        else:
            score += 10
            feedback_parts.append("Screenshot saved but might be empty or invalid")
    else:
        feedback_parts.append("Missing expected screenshot: congestion_map.png")

    # Settings XML Checks (20 points total)
    if result.get("settings_exists"):
        score += 10
        if result.get("settings_has_speed_coloring"):
            score += 10
            feedback_parts.append("Visualization settings exported with speed configuration")
        else:
            feedback_parts.append("Settings exported but missing 'speed' configuration")
    else:
        feedback_parts.append("Missing expected settings file: visualization_settings.xml")

    # Simulation Progress Check (20 points total)
    max_step = result.get("max_simulation_step", 0)
    if max_step >= min_time_step:
        score += 20
        feedback_parts.append(f"Simulation reached time step {max_step}")
    elif max_step > 0:
        score += 10
        feedback_parts.append(f"Simulation progressed but only to step {max_step} (expected >= {min_time_step})")
    else:
        feedback_parts.append("Simulation did not progress past step 0")

    # 3. Score Visual Criteria via VLM (40 points total)
    # Import locally to keep dependencies clean if not executed in right environment
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            images = frames + [final_frame] if final_frame else frames
            
            if images:
                vlm_resp = query_vlm(prompt=build_vlm_prompt(), images=images)
                
                if vlm_resp and vlm_resp.get("success"):
                    parsed = vlm_resp.get("parsed", {})
                    
                    if parsed.get("speed_coloring_active"):
                        score += 20
                        feedback_parts.append("VLM confirmed speed coloring active")
                    else:
                        feedback_parts.append("VLM did not detect speed coloring")
                        
                    if parsed.get("simulation_progressed"):
                        score += 10
                        feedback_parts.append("VLM confirmed vehicles moving")
                        
                    if parsed.get("settings_dialog_used"):
                        score += 10
                        feedback_parts.append("VLM observed settings dialog usage")
                else:
                    logger.warning("VLM query failed or returned invalid response")
                    feedback_parts.append("VLM verification failed")
            else:
                feedback_parts.append("No frames available for VLM verification")
        else:
            feedback_parts.append("VLM function not available in environment")
    except ImportError as e:
        logger.warning(f"Could not import gym_anything.vlm: {e}")
        feedback_parts.append("VLM modules unavailable")

    # Final Evaluation
    # Must have saved screenshot, exported speed settings, and advanced simulation
    key_criteria_met = (
        result.get("screenshot_exists") and 
        result.get("settings_has_speed_coloring") and 
        max_step >= min_time_step
    )
    
    passed = score >= 70 and key_criteria_met

    return {
        "passed": bool(passed),
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }