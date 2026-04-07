#!/usr/bin/env python3
"""
Verifier for the Create Annotated Presentation Image task in AstroImageJ.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_annotated_presentation_image(traj, env_info, task_info):
    """
    Verifies that the agent created an annotated, false-color PNG from the FITS file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Extract metadata
    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/AstroImages/processed/uit_presentation.png')

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. File Validations (20 Points)
    # ---------------------------------------------------------
    file_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    image_mode = result.get('image_mode', '')
    image_format = result.get('image_format', '')
    
    file_validations_passed = False
    
    if file_exists:
        if not file_created:
            feedback_parts.append("File exists but was NOT created during this task (possible cheating).")
        elif image_format != 'PNG':
            feedback_parts.append(f"File exists but is format {image_format}, expected PNG.")
        elif image_mode not in ['RGB', 'RGBA']:
            feedback_parts.append(f"File exists but image mode is {image_mode}. Expected RGB/RGBA (colorized).")
        else:
            score += 20
            feedback_parts.append("File validations passed (PNG, RGB, newly created).")
            file_validations_passed = True
    else:
        feedback_parts.append(f"Output file {expected_output_path} was NOT found.")
        # If the file wasn't even created, we can fail early
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }

    # ---------------------------------------------------------
    # VLM Visual & Trajectory Check
    # ---------------------------------------------------------
    # Import VLM utilities safely
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    except ImportError:
        logger.warning("VLM utilities not available. Assuming VLM checks fail.")
        return {"passed": False, "score": score, "feedback": "VLM utilities missing."}

    # Get trajectory frames and final screenshot
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    images = frames + [final_frame] if final_frame else frames

    if not images:
        feedback_parts.append("No screenshots available for VLM verification.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # VLM Prompt requesting JSON output
    vlm_prompt = """
    Analyze these screenshots of a user working in an astronomical imaging tool (AstroImageJ) and their final results.
    Return a JSON object with boolean values (true/false) for the following keys based on visual evidence:
    {
      "aij_used": "Is the AstroImageJ application interface visible and being actively used in the workflow?",
      "galaxy_visible": "Is the extended structure of the galaxy clearly visible in the image window (indicating proper contrast stretching, not just a black square or solid white)?",
      "fire_lut": "Is a warm false-color palette (like 'Fire', showing a spectrum of reds, oranges, and yellows) applied to the galaxy image?",
      "text_label_present": "Is the exact text 'UIT Galaxy Target' visibly annotated on the image?",
      "scale_bar_present": "Is there a scale bar (e.g., labeled '50 px') visibly annotated on the image?"
    }
    Respond ONLY with the raw JSON object. Do not include markdown blocks or explanations.
    """

    try:
        vlm_response = query_vlm(images=images, prompt=vlm_prompt)
        
        # Clean up response if it contains markdown formatting
        vlm_text = vlm_response.strip()
        if vlm_text.startswith("