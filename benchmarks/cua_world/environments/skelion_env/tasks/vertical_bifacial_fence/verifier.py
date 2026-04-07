#!/usr/bin/env python3
"""
Verifier for vertical_bifacial_fence task.

Uses a hybrid approach:
1. Programmatic validation of output file existence, size, and modification timestamp.
2. VLM trajectory verification to evaluate that a vertical (90-deg tilt) solar fence 
   was actually built and aligned to face East (Azimuth 90).
"""

import os
import json
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are evaluating an agent's completion of a SketchUp 3D modeling task using the Skelion solar plugin.
The task required creating an agrivoltaic "vertical solar fence".

Please analyze these trajectory screenshots (showing the progress and final state) and determine:
1. Did the agent draw a long rectangular strip on the ground (approx. 50x2 proportions)?
2. In the Skelion settings dialog (if visible), were the parameters "Tilt" set to 90 and "Azimuth" set to 90?
3. In the final modeling state, are there solar panels generated that stand VERTICALLY (at a 90-degree angle to the ground, like a fence) rather than lying flat/tilted?
4. Is the array aligned along the green axis (North-South) and do the faces of the panels point toward the red axis (East)?

Respond strictly in JSON format:
{
    "ground_strip_drawn": true/false,
    "tilt_and_azimuth_correct": true/false,
    "panels_are_vertical": true/false,
    "aligned_ns_facing_east": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of your visual findings"
}
"""

def verify_vertical_fence(traj, env_info, task_info):
    """
    Verify the vertical solar fence was designed correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    if not query_vlm:
        return {"passed": False, "score": 0, "feedback": "VLM query function not available"}

    # ================================================================
    # 1. Programmatic File Check
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Docker/Windows path usually translates C:\tmp to C:/tmp
        copy_from_env("C:/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON from container: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    file_exists = result.get('output_exists', False)
    file_modified = result.get('file_created_during_task', False)
    file_size_bytes = result.get('output_size_bytes', 0)
    
    score = 0
    feedback_parts = []

    if file_exists:
        score += 10
        feedback_parts.append("File 'vertical_fence.skp' exists")
        if file_modified:
            score += 15
            feedback_parts.append("File was saved during the task execution")
        else:
            feedback_parts.append("WARNING: File existed before task (Anti-gaming check failed)")
            
        if file_size_bytes > 30000: # 30 KB min for a Skelion generated array
            score += 10
            feedback_parts.append(f"File size is adequate ({file_size_bytes/1024:.1f} KB)")
        else:
            feedback_parts.append(f"File size is unusually small ({file_size_bytes/1024:.1f} KB), might be missing geometry")
    else:
        feedback_parts.append("Failed to find 'vertical_fence.skp' at expected path")
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts)
        }

    # ================================================================
    # 2. VLM Trajectory Verification
    # ================================================================
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    images = frames + [final_frame] if final_frame else frames

    if not images:
        feedback_parts.append("No screenshots available for VLM verification")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    vlm_result = query_vlm(
        prompt=VERIFICATION_PROMPT,
        images=images
    )

    if not vlm_result.get("success"):
        feedback_parts.append(f"VLM verification failed: {vlm_result.get('error')}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    parsed = vlm_result.get("parsed", {})
    
    strip_drawn = parsed.get("ground_strip_drawn", False)
    settings_correct = parsed.get("tilt_and_azimuth_correct", False)
    vertical_panels = parsed.get("panels_are_vertical", False)
    aligned_correctly = parsed.get("aligned_ns_facing_east", False)

    vlm_score = 0
    if strip_drawn:
        vlm_score += 10
        feedback_parts.append("VLM: Ground strip correctly drawn")
    
    if settings_correct:
        vlm_score += 20
        feedback_parts.append("VLM: Skelion tilt and azimuth observed correctly")
        
    if vertical_panels:
        vlm_score += 25
        feedback_parts.append("VLM: Panels successfully generated as a vertical fence")
        
    if aligned_correctly:
        vlm_score += 10
        feedback_parts.append("VLM: Orientation/Alignment is correct")

    score += vlm_score

    # To pass: File must be created/modified, and panels MUST be vertical (the core requirement)
    key_criteria_met = file_exists and file_modified and vertical_panels
    passed = score >= 65 and key_criteria_met

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "details": {
            "file_size": file_size_bytes,
            "vlm_parsed": parsed
        }
    }