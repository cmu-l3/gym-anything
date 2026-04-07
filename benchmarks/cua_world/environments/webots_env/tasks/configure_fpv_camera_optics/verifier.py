#!/usr/bin/env python3
"""
Verifier for configure_fpv_camera_optics task.

Tests that the agent configured camera optical flaws (noise, motion blur) 
and correctly instantiated a nested Lens node with radial distortion coefficients.
Also uses VLM to verify that the Webots GUI was utilized, preventing simple scripting bypass.
"""

import json
import os
import tempfile
import logging
import math

# Use the framework's VLM tools
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logging.warning("gym_anything.vlm unavailable. VLM trajectory verification will be skipped.")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_vlm_prompt():
    return """Examine these trajectory frames from an agent interacting with the Webots 3D robotics simulator.

TASK: The agent was asked to configure optical properties of an 'fpv_camera' (noise, motionBlur) and add a 'Lens' node with specific radial coefficients.

Check the frames for evidence of the following graphical interactions:
1. Is the Webots Scene Tree (left panel) visible and actively being navigated/expanded by the agent?
2. Did the agent open the 'Add Node' dialog (a popup window) to add the Lens object?
3. Did the agent modify values in the Field Editor (bottom left/right panel) below the Scene Tree?
4. Is there evidence of the 'Save World As' dialog being used?

Respond with a JSON object:
{
    "scene_tree_navigated": true/false,
    "add_node_dialog_seen": true/false,
    "field_editor_used": true/false,
    "save_dialog_seen": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what visual evidence proves GUI interaction."
}
"""


def verify_configure_fpv_camera_optics(traj, env_info, task_info):
    """
    Verify the fpv_camera was successfully degraded with the correct specs.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    
    # Expected values and tolerances
    exp_noise = metadata.get('expected_noise', 0.05)
    exp_blur = metadata.get('expected_motion_blur', 20.0)
    exp_rc1 = metadata.get('expected_radial_coeff_1', 0.35)
    exp_rc2 = metadata.get('expected_radial_coeff_2', -0.1)
    
    tol_noise = metadata.get('tolerance_noise', 0.01)
    tol_blur = metadata.get('tolerance_blur', 1.0)
    tol_radial = metadata.get('tolerance_radial', 0.05)

    score = 0
    feedback_parts = []
    
    # --- Step 1: Copy Exported Result JSON ---
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_file.name)
    except Exception as e:
        logger.warning(f"Could not load export result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results from environment."}

    # --- Step 2: Basic File Validation (10 points) ---
    if result.get("file_exists", False):
        if result.get("file_created_during_task", False):
            score += 10
            feedback_parts.append("World saved correctly")
        else:
            feedback_parts.append("World file exists but timestamp indicates it wasn't saved during the task")
    else:
        return {"passed": False, "score": 0, "feedback": "Target file /home/ga/Desktop/drone_fpv_realistic.wbt not found. The agent must save the world."}

    # Verify camera was actually found in the file
    if not result.get("camera_found", False):
        feedback_parts.append("Camera node 'fpv_camera' missing from saved world")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # --- Step 3: Noise Config (15 points) ---
    actual_noise = result.get("noise")
    if actual_noise is not None and math.isclose(actual_noise, exp_noise, abs_tol=tol_noise):
        score += 15
        feedback_parts.append(f"Noise set to {actual_noise}")
    else:
        feedback_parts.append(f"Noise incorrect (got {actual_noise}, expected {exp_noise})")

    # --- Step 4: Motion Blur Config (15 points) ---
    actual_blur = result.get("motion_blur")
    if actual_blur is not None and math.isclose(actual_blur, exp_blur, abs_tol=tol_blur):
        score += 15
        feedback_parts.append(f"Motion blur set to {actual_blur}")
    else:
        feedback_parts.append(f"Motion blur incorrect (got {actual_blur}, expected {exp_blur})")

    # --- Step 5: Lens Node Creation (20 points) ---
    if result.get("has_lens", False):
        score += 20
        feedback_parts.append("Lens node successfully added")
        
        # --- Step 6: Radial Coefficients (20 points) ---
        rc1 = result.get("radial_coeff_1")
        rc2 = result.get("radial_coeff_2")
        
        if rc1 is not None and rc2 is not None:
            if math.isclose(rc1, exp_rc1, abs_tol=tol_radial) and math.isclose(rc2, exp_rc2, abs_tol=tol_radial):
                score += 20
                feedback_parts.append(f"Radial coefficients correct: [{rc1}, {rc2}]")
            else:
                feedback_parts.append(f"Radial coefficients incorrect (got [{rc1}, {rc2}], expected [{exp_rc1}, {exp_rc2}])")
        else:
            feedback_parts.append("Radial coefficients missing in Lens node")
    else:
        feedback_parts.append("Lens node not found in fpv_camera")

    # --- Step 7: VLM Trajectory Verification (20 points) ---
    if VLM_AVAILABLE and traj:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                vlm_res = query_vlm(images=frames, prompt=build_vlm_prompt())
                if vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    
                    gui_score = 0
                    if parsed.get("scene_tree_navigated"): gui_score += 5
                    if parsed.get("add_node_dialog_seen"): gui_score += 5
                    if parsed.get("field_editor_used"): gui_score += 5
                    if parsed.get("save_dialog_seen"): gui_score += 5
                    
                    score += gui_score
                    if gui_score > 0:
                        feedback_parts.append("VLM verified GUI interactions")
                    else:
                        feedback_parts.append("VLM did not detect GUI usage (possible terminal spoofing)")
                else:
                    feedback_parts.append("VLM query failed, skipping trajectory points")
            else:
                feedback_parts.append("No trajectory frames available for VLM check")
        except Exception as e:
            logger.error(f"VLM Verification failed: {e}")
            feedback_parts.append("VLM exception during verification")
    else:
        # Give free points if VLM framework is disabled to prevent penalizing
        score += 20
        feedback_parts.append("VLM verification bypassed (framework limit)")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }