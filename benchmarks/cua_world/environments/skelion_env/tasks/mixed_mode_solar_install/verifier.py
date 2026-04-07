#!/usr/bin/env python3
"""
Verifier for mixed_mode_solar_install task.

Uses a robust Multi-Signal Verification Strategy:
1. File check: File existence, size validation, and anti-gaming timestamp checks
2. Visual check (VLM): Uses trajectory frame sampling to confirm geometric properties 
   and the dual Skelion layout configuration.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mixed_mode_solar(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ================================================================
    # Read telemetry JSON from the Windows container
    # ================================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    output_size = result.get('output_size_bytes', 0)
    
    score = 0
    feedback_parts = []
    
    # Check 1: Output File Checks
    if output_exists:
        score += 10
        feedback_parts.append("File mixed_mode_solar.skp exists")
    else:
        feedback_parts.append("File mixed_mode_solar.skp NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    if file_created:
        score += 10
        feedback_parts.append("File actively modified during task session")
    else:
        feedback_parts.append("File existed before task (possible gaming detected)")
        
    if output_size > 50000: # A SKP file with multiple components will easily exceed 50KB
        score += 10
        feedback_parts.append("File size indicates 3D geometry is present")
    else:
        feedback_parts.append("File too small (missing geometry or panels)")

    # ================================================================
    # VLM Verification on Trajectory Frames
    # ================================================================
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        feedback_parts.append("VLM query function not available")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    # Sample trajectory to ensure we see the geometry modeling phase AND final panels
    frames = sample_trajectory_frames(traj, n=5)
    final = get_final_screenshot(traj)
    images = frames + [final] if final else frames
    
    if not images:
        feedback_parts.append("No images available for VLM verification")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    prompt = """Analyze these trajectory screenshots from a SketchUp solar design task.
The user was asked to build two specific structures and place solar panels on them.

Look for the following criteria:
1. Are there TWO distinct buildings visible in the model?
2. Does one building have a sloped/pitched gable roof, and the other a flat roof?
3. Are there solar panels populated on BOTH roofs?
4. Are the panels on the sloped roof flush-mounted (lying flat parallel to the sloped surface)?
5. Are the panels on the flat roof tilted (standing up at an angle to the flat roof plane)?

Respond in JSON format:
{
  "two_buildings_visible": true/false,
  "sloped_and_flat_roofs_present": true/false,
  "panels_on_both_roofs": true/false,
  "sloped_panels_are_flush": true/false,
  "flat_panels_are_tilted": true/false,
  "reasoning": "Brief explanation of what you observe"
}
"""
    vlm_result = query_vlm(images=images, prompt=prompt)
    if not vlm_result.get("success"):
        feedback_parts.append(f"VLM verification failed: {vlm_result.get('error')}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    parsed = vlm_result.get("parsed", {})
    
    if parsed.get("two_buildings_visible"):
        score += 15
        feedback_parts.append("Both house and garage structures modeled")
    else:
        feedback_parts.append("Missing distinct buildings")
        
    if parsed.get("sloped_and_flat_roofs_present"):
        score += 15
        feedback_parts.append("Gable (sloped) and flat roof geometry verified")
    else:
        feedback_parts.append("Could not verify correct roof types")
        
    if parsed.get("panels_on_both_roofs"):
        score += 20
        feedback_parts.append("Solar panels deployed across both structures")
    else:
        feedback_parts.append("Panels are missing from one or both roofs")
        
    if parsed.get("sloped_panels_are_flush"):
        score += 10
        feedback_parts.append("House panels correctly flush-mounted")
        
    if parsed.get("flat_panels_are_tilted"):
        score += 10
        feedback_parts.append("Garage panels correctly tilted")
        
    # Core criteria must be met to pass
    core_criteria = (file_created and 
                     parsed.get("two_buildings_visible", False) and 
                     parsed.get("panels_on_both_roofs", False))
                     
    passed = score >= 70 and core_criteria
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {"vlm_parsed": parsed, "telemetry": result}
    }