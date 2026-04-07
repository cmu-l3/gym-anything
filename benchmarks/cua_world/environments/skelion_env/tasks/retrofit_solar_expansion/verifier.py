#!/usr/bin/env python3
"""
Verifier for the Retrofit Solar Expansion task.
Uses a hybrid approach: Programmatic file checks combined with VLM trajectory analysis 
to verify component placement and geometry.
"""

import os
import json
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are an expert solar design engineer evaluating a residential solar retrofit in SketchUp.

The agent was asked to:
1. Preserve an existing "legacy" solar array on the South-facing roof slope.
2. Design and place a new solar array on the adjacent West-facing roof slope using the Skelion plugin.
3. The new panels must be placed in Portrait orientation (taller than they are wide).

Please analyze the provided screenshot(s) of the SketchUp workspace and determine:
1. Is the original legacy array still present on one of the roof faces?
2. Has a NEW array of individual solar panels been added to a DIFFERENT, adjacent roof face (the West face)?
3. Are the panels in the newly added array oriented in Portrait (long edges running up/down the roof slope)?

Respond strictly in JSON format with these exact keys:
{
    "legacy_array_preserved": true/false,
    "new_array_on_different_face": true/false,
    "new_panels_in_portrait": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of your visual findings"
}
"""

def verify_retrofit_expansion(traj, env_info, task_info):
    """
    Verifies the SketchUp Skelion task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}
    if not query_vlm:
        return {"passed": False, "score": 0, "feedback": "System error: query_vlm not available"}

    score = 0
    feedback_parts = []
    
    # 1. Programmatic File Check
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file from container: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    file_size = result.get('output_size_bytes', 0)

    if output_exists:
        if file_created:
            score += 20
            feedback_parts.append("✅ Target file successfully saved")
        else:
            feedback_parts.append("❌ File exists but was not created/modified during the task")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
            
        if file_size > 50000:  # Valid SKP with multiple components will be > 50KB
            score += 10
            feedback_parts.append("✅ File size indicates valid geometry")
        else:
            feedback_parts.append("❌ File size is suspiciously small")
    else:
        feedback_parts.append("❌ Target file Smith_Residence_Retrofit.skp was NOT saved")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. VLM Trajectory Verification
    # Sample trajectory frames to ensure the work actually happened visually
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    images_to_analyze = frames + [final_frame] if final_frame else frames

    if not images_to_analyze:
        feedback_parts.append("❌ No visual evidence found for verification")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    vlm_result = query_vlm(
        prompt=VLM_PROMPT,
        images=images_to_analyze
    )

    if not vlm_result.get("success"):
        feedback_parts.append(f"❌ VLM error: {vlm_result.get('error')}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    parsed = vlm_result.get("parsed", {})
    legacy_preserved = parsed.get("legacy_array_preserved", False)
    new_array = parsed.get("new_array_on_different_face", False)
    portrait_mode = parsed.get("new_panels_in_portrait", False)

    if legacy_preserved:
        score += 20
        feedback_parts.append("✅ Legacy array successfully preserved")
    else:
        feedback_parts.append("❌ Legacy array missing or modified")

    if new_array:
        score += 30
        feedback_parts.append("✅ New array correctly placed on West face")
    else:
        feedback_parts.append("❌ Missing or incorrectly placed new array")

    if portrait_mode:
        score += 20
        feedback_parts.append("✅ Panels correctly oriented in Portrait")
    else:
        feedback_parts.append("❌ Panel orientation incorrect (likely Landscape)")

    # 3. Final Evaluation
    key_criteria_met = output_exists and file_created and new_array
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "vlm_reasoning": parsed.get("reasoning", "")
        }
    }