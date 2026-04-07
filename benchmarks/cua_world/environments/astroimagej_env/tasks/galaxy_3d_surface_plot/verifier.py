#!/usr/bin/env python3
"""
Verifier for galaxy_3d_surface_plot task in AstroImageJ.

Uses multi-criteria verification:
1. File programmatic checks (exists, correct size, modified during task, valid format).
2. Trajectory VLM checks (validates the process and visual representation).
"""

import os
import json
import logging
import tempfile

from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_galaxy_3d_surface_plot(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/AstroImages/processed/galaxy_core_surface.png')
    min_size = metadata.get('min_file_size_bytes', 5000)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Programmatic Verification (Copy and Parse JSON)
    # ---------------------------------------------------------
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    output_exists = result.get('output_exists', False)
    created_during_task = result.get('created_during_task', False)
    valid_image = result.get('valid_image', False)
    output_size = result.get('output_size_bytes', 0)
    
    if output_exists:
        if created_during_task:
            score += 15
            feedback_parts.append("File created successfully during task session.")
        else:
            feedback_parts.append("File exists but was modified BEFORE task started (Anti-gaming triggered).")
            # Immediate fail to prevent cheating
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
            
        if valid_image and output_size >= min_size:
            score += 15
            feedback_parts.append(f"Image is valid and reasonably sized ({output_size} bytes).")
        else:
            feedback_parts.append("Image is invalid or too small.")
    else:
        feedback_parts.append("Output file does NOT exist.")
        # Early exit if the output file wasn't created
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # ---------------------------------------------------------
    # 2. VLM Trajectory Verification
    # ---------------------------------------------------------
    # Extract frames across the workflow, plus the final state
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    images_for_vlm = frames + [final]
    
    # Attempt to pull the exported PNG from the environment and append it to the VLM context
    tmp_png = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        copy_from_env(expected_output_path, tmp_png.name)
        from PIL import Image
        out_img = Image.open(tmp_png.name)
        images_for_vlm.append(out_img)
    except Exception as e:
        logger.warning(f"Could not load output image for VLM context: {e}")
    finally:
        if os.path.exists(tmp_png.name):
            os.unlink(tmp_png.name)

    vlm_prompt = """
    Review the provided screenshot sequence representing a user's workflow in the software AstroImageJ, ending with the exported image artifact.
    The user's goal was:
    1. Draw a Region of Interest (ROI) around the bright central core of a galaxy.
    2. Apply a 'Fire' false-color Lookup Table (LUT) to map the intensities to a thermal gradient (blacks/reds/oranges/yellows/whites).
    3. Generate a 3D Surface Plot of this core.

    Based on visual evidence across the trajectory and the final exported image, evaluate if the user successfully achieved the visual goals.
    A successful 3D Surface Plot will show a 3D grid/mesh graph mapping image brightness to height, appearing as a peak in the center.
    
    Please answer with EXACTLY the following two lines (either YES or NO for each):
    SURFACE_PLOT_VISIBLE: [YES/NO]
    FIRE_LUT_APPLIED: [YES/NO]
    """

    try:
        vlm_response = query_vlm(images=images_for_vlm, prompt=vlm_prompt)
        response_upper = vlm_response.upper()
        
        surface_plot_visible = "SURFACE_PLOT_VISIBLE: YES" in response_upper
        fire_lut_applied = "FIRE_LUT_APPLIED: YES" in response_upper
        
        if surface_plot_visible:
            score += 40
            feedback_parts.append("VLM confirmed 3D surface plot is visible.")
        else:
            feedback_parts.append("VLM did not detect a 3D surface plot.")
            
        if fire_lut_applied:
            score += 30
            feedback_parts.append("VLM confirmed the Fire (thermal) LUT was applied.")
        else:
            feedback_parts.append("VLM did not detect the correct thermal LUT.")
            
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        feedback_parts.append(f"VLM check encountered an error: {e}")

    # Determine final pass/fail condition
    # Must have the file correctly generated and at least the surface plot validated visually
    key_criteria_met = output_exists and created_during_task and surface_plot_visible
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }