#!/usr/bin/env python3
"""
Verifier for Urban Row House Retrofit task in SketchUp Make 2017.

Verification Strategy:
1. File Verification (Anti-gaming): Checks if the .skp file exists, has a valid size, and was created during the task.
2. VLM Trajectory Verification: Samples frames to ensure the 3-unit modeling process took place.
3. VLM Final State Verification: Examines the final configuration to ensure geometry and panel constraints are met.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are an expert solar designer reviewing a SketchUp model for an urban row house retrofit.

Examine these screenshots of the SketchUp workspace (the last image is the final state).
Determine if the agent successfully modeled the required geometry and placed the solar panels correctly.

Look for the following criteria:
1. Is there a contiguous building block consisting of 3 attached units (bays) side-by-side?
2. Does the CENTER unit have raised parapet walls on the front/back and a stair bulkhead (a small rectangular box structure) on the roof?
3. Are there solar panels (usually blue or dark grid components created by Skelion) placed ONLY on the center unit? (No panels should be on the left or right neighbor units).
4. Do the solar panels actively avoid intersecting/overlapping with the stair bulkhead?
5. Are the solar panels visibly tilted at an angle (not completely flat flush against the roof)?

Provide your analysis in the following strict JSON format:
{
    "has_3_attached_units": true/false,
    "center_has_parapets_and_bulkhead": true/false,
    "panels_only_on_center": true/false,
    "panels_avoid_bulkhead": true/false,
    "panels_are_tilted": true/false,
    "reasoning": "Brief explanation of what you see in the model."
}
"""

def verify_urban_row_house_retrofit(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env or not query_vlm:
        return {"passed": False, "score": 0, "feedback": "Required framework functions (copy_from_env, query_vlm) missing"}

    metadata = task_info.get('metadata', {})
    min_size_kb = metadata.get('min_file_size_kb', 50)
    
    score = 0
    feedback_parts = []
    
    # -------------------------------------------------------------------------
    # 1. FILE & ANTI-GAMING VERIFICATION
    # -------------------------------------------------------------------------
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Use Windows path convention for the container
        copy_from_env("C:/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to read file validation result from environment."}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    file_exists = result.get('file_exists', False)
    created_during_task = result.get('file_created_during_task', False)
    file_size_kb = result.get('file_size_bytes', 0) / 1024.0

    if not file_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed: row_house_retrofit.skp was not saved."
        }
        
    if not created_during_task:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed: The file existed before the task and was not modified. (Anti-gaming triggered)"
        }

    score += 15
    feedback_parts.append("File saved successfully")

    if file_size_kb >= min_size_kb:
        score += 15
        feedback_parts.append(f"File size valid ({file_size_kb:.1f} KB)")
    else:
        feedback_parts.append(f"Warning: File size unusually small ({file_size_kb:.1f} KB)")
        
    # -------------------------------------------------------------------------
    # 2. VLM VISUAL VERIFICATION
    # -------------------------------------------------------------------------
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    images_to_evaluate = frames + [final_frame] if final_frame else frames
    
    if not images_to_evaluate:
        return {"passed": False, "score": score, "feedback": "No visual frames available for VLM verification"}

    vlm_result = query_vlm(
        images=images_to_evaluate,
        prompt=VLM_PROMPT
    )

    if not vlm_result.get('success'):
        feedback_parts.append(f"VLM check failed: {vlm_result.get('error')}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    parsed = vlm_result.get('parsed', {})
    logger.info(f"VLM Result: {parsed}")
    
    # -------------------------------------------------------------------------
    # 3. SCORING CRITERIA
    # -------------------------------------------------------------------------
    c_3_units = parsed.get("has_3_attached_units", False)
    c_center_features = parsed.get("center_has_parapets_and_bulkhead", False)
    c_panels_only_center = parsed.get("panels_only_on_center", False)
    c_avoid_bulkhead = parsed.get("panels_avoid_bulkhead", False)
    c_tilted = parsed.get("panels_are_tilted", False)

    if c_3_units:
        score += 10
        feedback_parts.append("3 units modeled")
    if c_center_features:
        score += 15
        feedback_parts.append("Bulkhead/Parapets modeled")
    if c_panels_only_center:
        score += 25
        feedback_parts.append("Panels targeted correctly to center")
    else:
        feedback_parts.append("ERROR: Panels placed outside target zone")
    if c_avoid_bulkhead:
        score += 10
        feedback_parts.append("Obstruction avoided")
    if c_tilted:
        score += 10
        feedback_parts.append("Panels tilted")

    # Critical constraints to pass: Must have saved the file AND put panels only on the center unit
    key_criteria_met = file_exists and c_panels_only_center and c_avoid_bulkhead
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) + f". Reasoning: {parsed.get('reasoning', 'None provided')}"
    }