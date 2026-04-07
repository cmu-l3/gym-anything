#!/usr/bin/env python3
"""
Verifier for tilt_angle_comparison_study task.

Uses a robust multi-signal strategy to prevent gaming:
1. Validates the existence, size, and timestamp of the generated .skp file.
2. Uses a Vision Language Model (VLM) evaluating trajectory frames to confirm 
   the presence of three distinct roof platforms and solar arrays.
3. Evaluates structural differences (tilt angles and corresponding row spacing) 
   via the VLM.
"""

import os
import json
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying an engineering task completed in SketchUp with the Skelion plugin.
The user was asked to create three separate flat roofs and place solar panels at 10, 20, and 30-degree tilts.

Review the provided screenshots of the workflow and the final result. Determine the following:
1. "three_roofs_present": Are there at least three distinct rectangular surfaces/platforms modeled? (true/false)
2. "panels_placed": Are there solar arrays placed on these three distinct surfaces? (true/false)
3. "varying_tilts": Do the arrays show visibly different steepness/tilt angles compared to each other? (true/false)
4. "varying_spacing": Does the inter-row spacing visibly increase on the steeper arrays to account for shading? (true/false)

Output your assessment as JSON exactly in this format:
{
    "three_roofs_present": boolean,
    "panels_placed": boolean,
    "varying_tilts": boolean,
    "varying_spacing": boolean,
    "confidence": "low|medium|high",
    "reasoning": "Brief explanation of what is visible in the frames."
}
"""

def verify_tilt_study(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available."}

    if not query_vlm:
        return {"passed": False, "score": 0, "feedback": "System error: query_vlm not available for visual verification."}

    score = 0
    feedback_parts = []
    
    # ==========================================
    # 1. Check File Metadata (Anti-Gaming)
    # ==========================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: using C:/ forward slashes for cross-compatibility in Docker wrapper
        copy_from_env("C:/Users/Docker/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    output_size_bytes = result.get('output_size_bytes', 0)
    
    metadata = task_info.get('metadata', {})
    min_size = metadata.get('min_file_size_bytes', 50000)

    if output_exists and file_created_during_task:
        score += 20
        feedback_parts.append("✅ File saved successfully during task")
    elif output_exists:
        feedback_parts.append("❌ File exists but was modified BEFORE task start (stale file)")
    else:
        feedback_parts.append("❌ Target file tilt_study.skp was not saved")
        
    if output_size_bytes >= min_size:
        score += 10
        feedback_parts.append(f"✅ File size acceptable ({output_size_bytes / 1024:.1f} KB)")
    elif output_exists:
        feedback_parts.append(f"❌ File size too small ({output_size_bytes / 1024:.1f} KB) - likely missing geometry")

    # ==========================================
    # 2. Visual / Spatial Verification via VLM
    # ==========================================
    # Use trajectory frames instead of just the final shot to prevent spoofing
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)

    if not frames:
        feedback_parts.append("❌ No trajectory frames available for VLM verification")
    else:
        vlm_response = query_vlm(images=frames, prompt=VLM_PROMPT)
        
        if vlm_response and vlm_response.get("success") and "parsed" in vlm_response:
            parsed = vlm_response["parsed"]
            
            # Criterion: Three distinct roofs
            if parsed.get("three_roofs_present", False):
                score += 20
                feedback_parts.append("✅ Three distinct roof surfaces detected")
            else:
                feedback_parts.append("❌ Could not verify three distinct roof surfaces")
                
            # Criterion: Panels placed
            if parsed.get("panels_placed", False):
                score += 20
                feedback_parts.append("✅ Solar arrays detected on surfaces")
            else:
                feedback_parts.append("❌ No solar panels detected on the roofs")
                
            # Criterion: Tilt & Spacing variation (The core objective of the task)
            if parsed.get("varying_tilts", False) and parsed.get("varying_spacing", False):
                score += 30
                feedback_parts.append("✅ Validated varying tilts and adaptive row spacing")
            elif parsed.get("varying_tilts", False):
                score += 15
                feedback_parts.append("⚠️ Varying tilts detected, but row spacing did not visibly adapt")
            else:
                feedback_parts.append("❌ Arrays do not show differing tilt configurations")
                
            feedback_parts.append(f"(VLM Reasoning: {parsed.get('reasoning', 'None provided')})")
        else:
            feedback_parts.append("❌ VLM parsing failed or returned invalid format")

    # ==========================================
    # 3. Final Evaluation
    # ==========================================
    key_criteria_met = output_exists and file_created_during_task and (score >= 70)
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }