#!/usr/bin/env python3
"""
Verifier for solar_window_awning_design task.

Uses a robust hybrid verification approach:
1. Programmatic checks on the exported .skp file (exists, created during task, valid size).
2. Trajectory VLM verification to confirm modeling steps and final visual output.
"""

import os
import json
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are an expert verifier evaluating a computer agent's 3D modeling task in SketchUp using the Skelion solar plugin.

TASK GOAL:
1. Model a vertical wall with a rectangular window opening.
2. Create an awning structure projecting from the wall immediately above the window.
3. The awning must be sloped/tilted downward (~20 degrees).
4. Insert solar panels on the awning using Skelion.

Look closely at the provided trajectory frames (showing the agent's work progress) and the final screenshot. Evaluate the following criteria:

1. WALL & WINDOW: Did the agent create a vertical face (wall) with a clear, smaller rectangular hole (window) cut out of it?
2. AWNING: Is there a distinct structural surface protruding outward from the wall, located above the window?
3. AWNING SLOPE: Does the awning clearly tilt/slope downward away from the wall?
4. SOLAR PANELS: Are there Skelion solar panels (typically dark/blue grid patterns) placed ON the surface of the awning?

Respond strictly in JSON format:
{
    "wall_and_window_visible": true/false,
    "awning_visible": true/false,
    "awning_is_sloped": true/false,
    "solar_panels_on_awning": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Briefly explain what evidence you see for each criterion"
}
"""

def verify_solar_awning(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Configuration error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    min_size_kb = metadata.get('min_file_size_kb', 25)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. FILE VERIFICATION
    # ---------------------------------------------------------
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Use Windows path format for the container
        copy_from_env("C:\\temp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    file_size_bytes = result.get('output_size_bytes', 0)
    file_size_kb = file_size_bytes / 1024

    if output_exists:
        if file_created:
            score += 20
            feedback_parts.append("✅ File created during task")
        else:
            feedback_parts.append("❌ File exists but was NOT modified during the task (Gaming detected)")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
            
        if file_size_kb > min_size_kb:
            score += 10
            feedback_parts.append(f"✅ File size acceptable ({file_size_kb:.1f} KB)")
        else:
            feedback_parts.append(f"❌ File size too small ({file_size_kb:.1f} KB) - likely missing geometry")
    else:
        feedback_parts.append("❌ Output file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # ---------------------------------------------------------
    # 2. VLM TRAJECTORY VERIFICATION
    # ---------------------------------------------------------
    if not query_vlm:
        feedback_parts.append("⚠️ VLM verification unavailable")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    images_to_evaluate = frames + [final_frame] if final_frame else frames

    if not images_to_evaluate:
        feedback_parts.append("❌ No screenshots available for VLM verification")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    try:
        vlm_result = query_vlm(prompt=VERIFICATION_PROMPT, images=images_to_evaluate)
        parsed = vlm_result.get("parsed", {})
        
        wall_window = parsed.get("wall_and_window_visible", False)
        awning = parsed.get("awning_visible", False)
        sloped = parsed.get("awning_is_sloped", False)
        panels = parsed.get("solar_panels_on_awning", False)
        
        vlm_criteria_met = 0
        
        if wall_window:
            score += 15
            vlm_criteria_met += 1
            feedback_parts.append("✅ Wall and window detected")
        else:
            feedback_parts.append("❌ Wall/window not detected")
            
        if awning:
            score += 15
            vlm_criteria_met += 1
            feedback_parts.append("✅ Awning detected")
        else:
            feedback_parts.append("❌ Awning not detected")
            
        if sloped:
            score += 20
            vlm_criteria_met += 1
            feedback_parts.append("✅ Awning slope detected")
        else:
            feedback_parts.append("❌ Awning slope not detected")
            
        if panels:
            score += 20
            vlm_criteria_met += 1
            feedback_parts.append("✅ Solar panels detected on awning")
        else:
            feedback_parts.append("❌ Solar panels not detected on awning")

    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        feedback_parts.append(f"⚠️ VLM Error: {e}")
        vlm_criteria_met = 0

    # ---------------------------------------------------------
    # 3. FINAL EVALUATION
    # ---------------------------------------------------------
    # Task requires File creation, Awning existence, and Panel placement to pass.
    # Total possible score is 100. Pass threshold is 75.
    
    key_criteria_met = output_exists and file_created and awning and panels
    passed = score >= 75 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "file_size_kb": file_size_kb,
            "vlm_reasoning": parsed.get("reasoning", "") if 'parsed' in locals() else ""
        }
    }