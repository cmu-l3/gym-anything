#!/usr/bin/env python3
"""
Verifier for t_shaped_commercial_solar task in SketchUp + Skelion.

ROBUST MULTI-SIGNAL VERIFICATION:
1. File saved to exact expected path (10 pts)
2. File created DURING the task (timestamp check, anti-gaming) (10 pts)
3. File size exceeds threshold indicating real content (10 pts)
4. VLM: Confirms presence of a 3D T-shaped building in trajectory (35 pts)
5. VLM: Confirms Skelion solar panels populated on the roof (35 pts)

Pass Threshold: 70 points (Requires either perfect modeling confirmation + file existence, 
or partial modeling with all file/size/timestamp criteria met)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are an expert evaluating a 3D modeling task in SketchUp.
The user was instructed to:
1. Create a 3D building with a clearly T-shaped footprint (viewed from above or at an angle).
2. Use the Skelion plugin to place a grid of solar panels on the flat roof of this building.

Analyze these screenshots from the user's session trajectory.
Carefully look at the 3D geometry and the presence of roof objects.

Determine if the trajectory shows:
1. A 3D building with a clearly T-shaped footprint.
2. Solar panels placed on the roof surface.

Respond in strict JSON format:
{
    "has_t_shape_building": true/false,
    "has_solar_panels_on_roof": true/false,
    "reasoning": "Brief explanation of what geometric shapes and panel placements are visible."
}
"""

def verify_t_shaped_solar(traj, env_info, task_info):
    """
    Evaluates the trajectory and exported task data for successful completion.
    Uses copy_from_env to safely retrieve the JSON exported by PowerShell.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verifier error: copy_from_env function not available"}
    if not query_vlm:
        return {"passed": False, "score": 0, "feedback": "Verifier error: query_vlm function not available"}

    # Extract metadata constraints
    metadata = task_info.get('metadata', {})
    min_size_bytes = metadata.get('min_file_size_bytes', 76800)  # ~75 KB

    # 1. Retrieve the exported JSON from the Windows container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # File paths inside the Windows container use backslashes usually, or standard paths
        copy_from_env("C:\\Temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # 2. Programmatic File Evaluation (30 points)
    output_exists = result.get('output_exists', False)
    created_during_task = result.get('file_created_during_task', False)
    file_size = result.get('output_size_bytes', 0)

    if output_exists:
        score += 10
        feedback_parts.append("✅ File successfully saved")
        
        if created_during_task:
            score += 10
            feedback_parts.append("✅ File timestamp validates it was created during session")
        else:
            feedback_parts.append("❌ File existed before task (possible pre-plant/gaming)")
            
        if file_size >= min_size_bytes:
            score += 10
            feedback_parts.append(f"✅ File size adequate ({file_size/1024:.1f} KB)")
        else:
            feedback_parts.append(f"❌ File size too small ({file_size/1024:.1f} KB) - lacking 3D/panel data")
    else:
        feedback_parts.append("❌ Output file not found")

    # 3. Visual Verification using Trajectory (70 points)
    # We import these at the function level per framework guidelines
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    images = frames + [final] if final else frames
    
    if not images:
        feedback_parts.append("❌ No screenshots available for VLM verification")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    vlm_response = query_vlm(prompt=VERIFICATION_PROMPT, images=images)
    
    if vlm_response and vlm_response.get("success"):
        parsed = vlm_response.get("parsed", {})
        has_t_shape = parsed.get("has_t_shape_building", False)
        has_panels = parsed.get("has_solar_panels_on_roof", False)
        
        if has_t_shape:
            score += 35
            feedback_parts.append("✅ VLM confirmed T-shaped building")
        else:
            feedback_parts.append("❌ VLM did not detect T-shaped geometry")
            
        if has_panels:
            score += 35
            feedback_parts.append("✅ VLM confirmed solar panels on roof")
        else:
            feedback_parts.append("❌ VLM did not detect solar panels on roof")
            
        logger.info(f"VLM Reasoning: {parsed.get('reasoning', 'None provided')}")
    else:
        feedback_parts.append("❌ VLM verification failed to process")

    # 4. Determine Pass/Fail (Requires at least 70 points and the file must exist)
    key_criteria_met = output_exists and score >= 70
    passed = key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }