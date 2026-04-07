#!/usr/bin/env python3
"""
Verifier for configure_panel_azimuth task.

MULTI-SIGNAL VERIFICATION:
1. File Existence & Timestamps (Anti-gaming check)
2. File Size Increase (Adding solar panel geometries heavily increases file size over base building)
3. VLM Trajectory Verification:
   - Skelion dialog was interacted with
   - Parameters (Azimuth 225, Tilt 20) were populated
   - Final panels are visually tilted and rotated southwest (not grid-aligned)
"""

import os
import json
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are an expert evaluating a SketchUp and Skelion solar design workflow.
The user was asked to place solar panels on a flat-roofed building with an Azimuth of 225° (southwest) and a Tilt of 20°.

Review the provided screenshots (trajectory frames and the final state) and analyze the workflow:
1. Did the user open the Skelion plugin dialog/settings at some point?
2. Are the specific parameters "225" (Azimuth) and "20" (Tilt) visible in the Skelion configuration dialog?
3. Are solar panels successfully inserted on the top flat roof of the building?
4. Do the panels appear to be correctly oriented southwest? (They should be rotated diagonally relative to the square edges of the building roof, not perfectly parallel to the main walls).

Respond ONLY with a JSON object in this format:
{
    "skelion_dialog_opened": boolean,
    "correct_parameters_entered": boolean,
    "panels_inserted_on_roof": boolean,
    "panels_visually_rotated_southwest": boolean,
    "reasoning": "Brief explanation of your observations"
}
"""

def verify_configure_panel_azimuth(traj, env_info, task_info):
    """
    Evaluates the Skelion azimuth setup task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env or not query_vlm:
        return {"passed": False, "score": 0, "feedback": "Required evaluation functions not available."}

    # Extract result JSON created by export_result.ps1
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. FILE CHECKS (Anti-gaming)
    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    file_size = result.get('output_size_bytes', 0)
    
    if output_exists and file_created:
        score += 20
        feedback_parts.append("✅ Model saved during task")
    elif output_exists:
        feedback_parts.append("❌ File existed before task start (not created by agent)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    else:
        feedback_parts.append("❌ Target model file was not saved")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. FILE SIZE CHECK (Panels add geometry)
    # The base flat roof box is typically ~20-25KB in SU2017. 
    # With a moderate panel array, size should jump by at least 30KB.
    if file_size > 55000:
        score += 20
        feedback_parts.append(f"✅ Model size ({file_size//1024}KB) indicates panels were added")
    else:
        feedback_parts.append(f"❌ Model size ({file_size//1024}KB) too small; panels likely missing")

    # 3. VLM TRAJECTORY ANALYSIS
    frames = sample_trajectory_frames(traj, n=5)
    final_frame = get_final_screenshot(traj)
    images_to_analyze = frames + [final_frame] if final_frame else frames

    vlm_result = query_vlm(
        prompt=VLM_PROMPT,
        images=images_to_analyze
    )

    if not vlm_result.get("success"):
        feedback_parts.append(f"⚠️ VLM verification failed: {vlm_result.get('error', 'Unknown')}")
    else:
        parsed = vlm_result.get("parsed", {})
        
        dialog_opened = parsed.get("skelion_dialog_opened", False)
        params_entered = parsed.get("correct_parameters_entered", False)
        panels_inserted = parsed.get("panels_inserted_on_roof", False)
        rotated_sw = parsed.get("panels_visually_rotated_southwest", False)
        
        if dialog_opened:
            score += 10
            feedback_parts.append("✅ Skelion dialog opened")
            
        if params_entered:
            score += 20
            feedback_parts.append("✅ Azimuth=225 and Tilt=20 parameters configured")
        else:
            feedback_parts.append("❌ Correct parameters not seen in Skelion dialog")
            
        if panels_inserted and rotated_sw:
            score += 30
            feedback_parts.append("✅ Panels successfully placed and visually oriented southwest")
        elif panels_inserted:
            score += 10
            feedback_parts.append("⚠️ Panels inserted but orientation appears incorrect (not southwest)")
        else:
            feedback_parts.append("❌ Panels were not successfully inserted")

    passed = score >= 60 and output_exists and parsed.get("panels_inserted_on_roof", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }