#!/usr/bin/env python3
"""
Verifier for the Quonset Hut Solar Retrofit task.

ROBUST MULTI-SIGNAL VERIFICATION:
1. File check: Assesses existence, size, and timestamp of the saved SketchUp file.
2. Trajectory VLM: Verifies the agent's process (e.g., viewing hidden geometry, selecting curved segments).
3. Final State VLM: Verifies the resulting model's geometry and panel placement (detecting panels that follow a curve).

The verification correctly enforces anti-gaming by heavily weighting the trajectory progression.
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TRAJ_PROMPT = """You are verifying the workflow of an agent using SketchUp and the Skelion solar plugin. 
The task is to build a Quonset hut (semi-cylindrical building) and place solar panels on the curved roof.

Review these trajectory frames and determine the following:
1. Did the agent construct a semi-cylindrical/curved building?
2. Did the agent interact with the curved surface segments (e.g., enabling "Hidden Geometry" to reveal the facets, or selecting specific angled segments)?
3. Did the agent place solar panels onto the model using Skelion?

Respond ONLY in valid JSON format with the following boolean keys:
{
    "built_cylinder": true/false,
    "interacted_with_segments": true/false,
    "placed_panels": true/false
}
"""

FINAL_PROMPT = """You are verifying the final state of a SketchUp solar design task.
The user was supposed to place solar panels on the south-facing side of a Quonset hut (semi-cylindrical curved roof).

Review this final screenshot and determine the following:
1. Is a semi-cylindrical (curved roof) building clearly visible?
2. Are solar panels placed on the roof?
3. Do the panels physically follow the curve of the roof? (They should be mounted on multiple different angled segments, rather than floating entirely flat on a single plane above it).

Respond ONLY in valid JSON format with the following boolean keys:
{
    "has_quonset_hut": true/false,
    "has_panels": true/false,
    "panels_follow_curve": true/false
}
"""

def verify_quonset_hut_solar(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env or not query_vlm:
        return {"passed": False, "score": 0, "feedback": "Required framework functions not available."}

    score = 0
    feedback_parts = []
    
    # ================================================================
    # 1. FILE & TIMESTAMP VERIFICATION
    # ================================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Using the Windows path standard for Docker containers
        copy_from_env("C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read file metrics result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    output_size_bytes = result.get('output_size_bytes', 0)
    
    if output_exists and output_size_bytes > 50000:
        score += 20
        feedback_parts.append("Valid model file saved")
    elif output_exists:
        score += 10
        feedback_parts.append("File saved but size is suspiciously small")
    else:
        feedback_parts.append("File NOT saved")
        
    if file_created_during_task:
        score += 10
        feedback_parts.append("File modified during task timeline")
    elif output_exists:
        feedback_parts.append("File predates task start (Failed timestamp anti-gaming)")

    # ================================================================
    # 2. VLM TRAJECTORY VERIFICATION
    # ================================================================
    frames = sample_trajectory_frames(traj, n=6)
    if frames:
        traj_result = query_vlm(images=frames, prompt=TRAJ_PROMPT)
        if traj_result and traj_result.get("success"):
            parsed_traj = traj_result.get("parsed", {})
            if parsed_traj.get("built_cylinder", False):
                score += 10
            if parsed_traj.get("interacted_with_segments", False):
                score += 10
                feedback_parts.append("Curve segmentation workflow detected")
            if parsed_traj.get("placed_panels", False):
                score += 10
        else:
            feedback_parts.append("Trajectory VLM parsing failed")

    # ================================================================
    # 3. VLM FINAL STATE VERIFICATION
    # ================================================================
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        final_result = query_vlm(images=[final_screenshot], prompt=FINAL_PROMPT)
        if final_result and final_result.get("success"):
            parsed_final = final_result.get("parsed", {})
            
            has_quonset_hut = parsed_final.get("has_quonset_hut", False)
            has_panels = parsed_final.get("has_panels", False)
            panels_follow_curve = parsed_final.get("panels_follow_curve", False)
            
            if has_quonset_hut:
                score += 10
                feedback_parts.append("Quonset hut structure verified")
            if has_panels:
                score += 10
                feedback_parts.append("Solar panels present")
            if panels_follow_curve:
                score += 20
                feedback_parts.append("Panels successfully follow curvature")
            elif has_panels:
                feedback_parts.append("Panels are flat/not following curve constraint")
        else:
            feedback_parts.append("Final state VLM parsing failed")

    # ================================================================
    # EVALUATION LOGIC
    # ================================================================
    # Must meet key criteria: File must exist, panels must be present, panels must be curved
    key_criteria_met = (
        output_exists and 
        file_created_during_task and
        parsed_final.get("has_panels", False) and 
        parsed_final.get("panels_follow_curve", False)
    )
    
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }