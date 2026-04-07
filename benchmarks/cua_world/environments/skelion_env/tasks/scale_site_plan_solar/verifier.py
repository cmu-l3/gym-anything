#!/usr/bin/env python3
"""
Verifier for the Scale Site Plan Solar task.

This verifier checks:
1. Anti-gaming: File was saved during the task execution.
2. Scale Accuracy: The building's footprint dimensions expanded from 1m to ~20m.
3. 3D Extrusion: The building was extruded vertically to roughly 6m.
4. Solar Placement: Skelion components (panels) were placed (count > 10).
5. Visual Verification: VLM confirms the workflow steps and final state.
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """
You are evaluating an agent's performance in SketchUp.
Task: The agent had to rescale a miniaturized 2D site plan, extrude it into a 3D building, and place solar panels on the roof using the Skelion plugin.

Review the trajectory frames and final screenshot to determine:
1. Did the agent use the Tape Measure tool or Scale tool to resize the model?
2. Is there a 3D building (extruded upward from a flat plan)?
3. Are there visible solar panels placed on the roof?

Respond ONLY with a valid JSON object matching this schema:
{
    "scaled_model": true/false,
    "extruded_3d_building": true/false,
    "panels_visible": true/false,
    "confidence": "low/medium/high",
    "reasoning": "brief explanation"
}
"""

def verify_scale_site_plan(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve programmatic results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(r"C:\tmp\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # File Checks
    file_exists = result.get("file_exists", False)
    file_created = result.get("file_created_during_task", False)
    
    if not file_exists:
        return {"passed": False, "score": 0, "feedback": "Target SketchUp file was not saved."}
    if not file_created:
        feedback_parts.append("Warning: File was not created/modified during the task window.")
    else:
        score += 10
        feedback_parts.append("File correctly saved.")

    # Model Evaluation Checks
    eval_data = result.get("evaluation", {})
    bounds_x = eval_data.get("bounds_x_m", 0.0)
    bounds_y = eval_data.get("bounds_y_m", 0.0)
    bounds_z = eval_data.get("bounds_z_m", 0.0)
    panel_count = eval_data.get("panel_count", 0)

    # 2. Verify Scale (Target ~20m on largest dimension)
    max_dim = max(bounds_x, bounds_y)
    if 18.0 <= max_dim <= 24.0:
        score += 30
        feedback_parts.append(f"Model scaled correctly (Max Dim: {max_dim:.1f}m)")
    elif max_dim > 2.0:
        score += 10
        feedback_parts.append(f"Model partially scaled/incorrect scale (Max Dim: {max_dim:.1f}m)")
    else:
        feedback_parts.append(f"Model not scaled (Max Dim remains {max_dim:.1f}m)")

    # 3. Verify Extrusion (Target ~6m height + panels)
    if 5.0 <= bounds_z <= 15.0:
        score += 20
        feedback_parts.append(f"Building extruded to expected height (Z: {bounds_z:.1f}m)")
    elif bounds_z > 1.0:
        score += 10
        feedback_parts.append(f"Building extruded but wrong height (Z: {bounds_z:.1f}m)")
    else:
        feedback_parts.append("Building not extruded (remains 2D).")

    # 4. Verify Panel Count
    if panel_count >= 10:
        score += 20
        feedback_parts.append(f"Solar panels placed successfully (Count: {panel_count})")
    elif panel_count > 0:
        score += 10
        feedback_parts.append(f"Some solar panels placed, but below expected count (Count: {panel_count})")
    else:
        feedback_parts.append("No solar panels detected.")

    # 5. Visual Verification using VLM
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        
        if final:
            vlm_response = query_vlm(
                prompt=VERIFICATION_PROMPT,
                images=frames + [final]
            )
            
            if vlm_response.get('success'):
                vlm_parsed = vlm_response.get('parsed', {})
                if vlm_parsed.get('scaled_model'):
                    score += 5
                if vlm_parsed.get('extruded_3d_building'):
                    score += 5
                if vlm_parsed.get('panels_visible'):
                    score += 10
                feedback_parts.append(f"VLM visual check: {vlm_parsed.get('reasoning', 'No reasoning provided')}")
            else:
                feedback_parts.append(f"VLM query failed: {vlm_response.get('error')}")

    # Final Evaluation
    passed = score >= 80 and panel_count >= 10 and max_dim >= 18.0
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }