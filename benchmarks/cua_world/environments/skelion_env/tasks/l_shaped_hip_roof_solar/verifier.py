#!/usr/bin/env python3
"""
Verifier for the L-Shaped Hip Roof Solar task in SketchUp (Skelion).
Combines file existence/timestamp verification with VLM trajectory analysis
to ensure the agent actually modeled the correct geometry and placed panels.
"""

import os
import json
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are an expert SketchUp and Solar Design evaluator.
I am providing you with frames from an agent's trajectory working in SketchUp, and the final state.

The agent was tasked with:
1. Modeling an L-shaped residential building footprint.
2. Extruding it into 3D walls.
3. Modeling a HIP ROOF on top (slopes on all sides toward the center, no flat vertical gable walls).
4. Using the Skelion plugin to install solar panels on the South-facing roof slopes.

Review the images and evaluate the following criteria. Be strict.

CRITERIA:
1. is_l_shaped_building: Did the agent construct a 3D building with an L-shaped footprint? (True/False)
2. is_hip_roof: Does the building have a hip roof? (Must be sloped on all sides. If you see vertical triangular walls at the ends of the roof, that is a gable roof, which is FALSE). (True/False)
3. panels_present: Are solar panels (rectangular grid components) visible on the roof? (True/False)
4. panels_on_correct_face: Are the panels placed specifically on the correct roof facets? (True/False)

Provide your response strictly in the following JSON format:
{
    "is_l_shaped_building": true/false,
    "is_hip_roof": true/false,
    "panels_present": true/false,
    "panels_on_correct_face": true/false,
    "reasoning": "brief explanation of your observations"
}
"""

def verify_l_shaped_hip_roof_solar(traj, env_info, task_info):
    """
    Multi-signal verification for the SketchUp Skelion task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    if not query_vlm:
        return {"passed": False, "score": 0, "feedback": "VLM function not available"}

    feedback_parts = []
    score = 0
    max_score = 100
    
    # 1. Evaluate file metadata
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\Documents\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    file_exists = result.get('file_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    file_size_bytes = result.get('file_size_bytes', 0)
    
    # Anti-gaming & basic completion
    if not file_exists:
        return {"passed": False, "score": 0, "feedback": "FAIL: Target .skp file was not saved."}
        
    score += 10
    feedback_parts.append("File saved")
    
    if file_created_during_task:
        score += 10
        feedback_parts.append("File created during session")
    else:
        feedback_parts.append("WARNING: File existed before task start")
        
    if file_size_bytes > 30000: # Bare empty SketchUp file is ~15-20KB. With geometry+panels it jumps higher.
        score += 10
        feedback_parts.append(f"File size valid ({file_size_bytes//1024}KB)")
    else:
        feedback_parts.append(f"File suspiciously small ({file_size_bytes//1024}KB)")

    # 2. Evaluate Visual Evidence (VLM)
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    images = frames + [final_frame] if final_frame else frames
    
    if not images:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + " | No visual evidence available."}

    vlm_resp = query_vlm(prompt=VERIFICATION_PROMPT, images=images)
    
    if not vlm_resp.get("success"):
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + f" | VLM Error: {vlm_resp.get('error')}"}

    parsed = vlm_resp.get("parsed", {})
    is_l_shaped = parsed.get("is_l_shaped_building", False)
    is_hip_roof = parsed.get("is_hip_roof", False)
    panels_present = parsed.get("panels_present", False)
    panels_correct = parsed.get("panels_on_correct_face", False)
    
    if is_l_shaped:
        score += 20
        feedback_parts.append("L-shaped footprint confirmed")
    else:
        feedback_parts.append("L-shaped footprint missing/incorrect")
        
    if is_hip_roof:
        score += 20
        feedback_parts.append("Hip roof geometry confirmed")
    else:
        feedback_parts.append("Hip roof missing/incorrect (possibly gable or flat)")
        
    if panels_present:
        score += 15
        feedback_parts.append("Solar panels present")
    else:
        feedback_parts.append("No solar panels visible")
        
    if panels_correct:
        score += 15
        feedback_parts.append("Panels on valid slope")
    else:
        feedback_parts.append("Panel placement incorrect/missing")

    # Final logic
    passed = score >= 65 and is_l_shaped and is_hip_roof and panels_present and file_exists

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "vlm_reasoning": parsed.get("reasoning", "No reasoning provided.")
        }
    }