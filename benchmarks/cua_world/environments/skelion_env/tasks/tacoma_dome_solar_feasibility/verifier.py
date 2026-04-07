#!/usr/bin/env python3
"""
Verifier for Tacoma Dome Solar Feasibility task.
Combines programmatic Ruby API analysis (panel counts, geometric normals) 
with VLM verification (trajectory and visual state) to ensure the 
panels correctly map to the curved, south-facing dome geometry.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt specifically checking trajectory and final state for proper mapping
VLM_PROMPT = """You are evaluating an agent's success in mapping solar panels to a 3D dome in SketchUp using the Skelion plugin.
Look at the sequence of trajectory frames and the final screenshot. 

Please verify:
1. Are solar panels (dark, grid-like textured rectangles) placed on the dome structure?
2. Do the panels smoothly conform to the curved surface of the dome (flush-mounted), rather than sticking straight up or floating in the air?
3. Are the panels isolated mostly to ONE SIDE of the dome (the south-facing half)?

Provide a JSON response with:
{
    "panels_present": true/false,
    "panels_flush_curved": true/false,
    "panels_on_one_side": true/false,
    "reasoning": "brief explanation"
}
"""

def verify_tacoma_dome_solar(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_panels = metadata.get('min_panels_expected', 50)
    y_threshold = metadata.get('orientation_south_y_threshold', -0.1)
    variance_thresh = metadata.get('curvature_variance_threshold', 0.005)
    
    score = 0
    feedback_parts = []
    
    # Read the exported JSON result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 1. File existence and anti-gaming (20 pts)
    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    
    if output_exists:
        if file_created_during_task:
            score += 20
            feedback_parts.append("✅ Output model correctly saved")
        else:
            feedback_parts.append("❌ Model exists but was not modified during the task")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    else:
        feedback_parts.append("❌ Output model 'tacoma_dome_solar_mapped.skp' not found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 2. PV Components Present (20 pts)
    panel_count = result.get('panel_count', 0)
    if panel_count >= min_panels:
        score += 20
        feedback_parts.append(f"✅ Panels detected ({panel_count})")
    elif panel_count > 0:
        score += 10
        feedback_parts.append(f"⚠️ Insufficient panels detected ({panel_count})")
    else:
        feedback_parts.append("❌ No Skelion PV components found in model")

    # 3. South Orientation Check via Y-normals (20 pts)
    # SketchUp Green Axis is North (+Y). South is -Y.
    y_avg = result.get('y_avg', 0)
    if panel_count > 0:
        if y_avg <= y_threshold:
            score += 20
            feedback_parts.append(f"✅ Panels oriented South (Y_avg: {y_avg:.3f})")
        else:
            feedback_parts.append(f"❌ Panels not correctly isolated to South face (Y_avg: {y_avg:.3f})")

    # 4. Curvature / Flush Mount Check via Z-variance (20 pts)
    # If the panels are flush on a sphere, their Z-normals will vary heavily.
    # If they placed them on a flat plane or with a uniform rack tilt, variance is ~0.
    z_variance = result.get('z_variance', 0)
    if panel_count > 0:
        if z_variance >= variance_thresh:
            score += 20
            feedback_parts.append(f"✅ Panels conform to curved surface (Variance: {z_variance:.4f})")
        else:
            feedback_parts.append(f"❌ Panels appear completely flat, failed to flush-mount to dome (Variance: {z_variance:.4f})")

    # 5. VLM Visual Trajectory Verification (20 pts)
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    query_vlm = env_info.get('query_vlm')
    vlm_passed = False
    
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=3)
        final_frame = get_final_screenshot(traj)
        
        if final_frame:
            images = frames + [final_frame]
            vlm_result = query_vlm(prompt=VLM_PROMPT, images=images)
            
            if vlm_result.get("success"):
                vlm_data = vlm_result.get("parsed", {})
                if vlm_data.get("panels_present") and vlm_data.get("panels_flush_curved"):
                    score += 20
                    vlm_passed = True
                    feedback_parts.append("✅ VLM visually confirmed flush panels on dome")
                else:
                    feedback_parts.append("❌ VLM rejected visual state: " + vlm_data.get("reasoning", "Panel mapping failed"))
            else:
                feedback_parts.append("⚠️ VLM evaluation failed to process")
        else:
            feedback_parts.append("⚠️ No final screenshot for VLM")
    
    # Evaluate Pass/Fail
    # To pass, they must have saved the file, placed enough panels, 
    # and passed either the geometric math checks OR visual confirmation.
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "panel_count": panel_count,
            "y_avg": y_avg,
            "z_variance": z_variance,
            "vlm_passed": vlm_passed
        }
    }