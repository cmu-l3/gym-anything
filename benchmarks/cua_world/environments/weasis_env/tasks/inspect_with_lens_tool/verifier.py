#!/usr/bin/env python3
"""
Verifier for inspect_with_lens_tool task.
Verifies programmatic file outputs AND uses VLM trajectory verification
to ensure the Lens tool was actively used.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM utilities from gym_anything
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    logger.warning("Could not import gym_anything.vlm utilities directly.")

def verify_inspect_with_lens(traj, env_info, task_info):
    # Retrieve framework copy tool
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_file_size_kb = metadata.get('min_file_size_kb', 50)
    expected_output_path = metadata.get('expected_output_path', '/home/ga/DICOM/exports/lens_inspection.png')

    score = 0
    feedback_parts = []
    
    # 1. READ PROGRAMMATIC JSON RESULT
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Variables for grading
    output_exists = result.get('output_exists', False)
    valid_png = result.get('valid_png', False)
    created_during = result.get('file_created_during_task', False)
    output_size_bytes = int(result.get('output_size_bytes', 0))
    output_size_kb = output_size_bytes / 1024.0

    # PROGRAMMATIC SCORING
    if output_exists and valid_png:
        score += 20
        feedback_parts.append("Valid PNG saved")
    else:
        feedback_parts.append("Target PNG not found or invalid")

    if created_during:
        score += 20
        feedback_parts.append("File created during task (anti-gaming)")
    else:
        feedback_parts.append("File not created during task")

    if output_size_kb >= min_file_size_kb:
        score += 10
        feedback_parts.append(f"Size OK ({output_size_kb:.1f}KB)")
    elif output_exists:
        score += 5
        feedback_parts.append(f"Size too small ({output_size_kb:.1f}KB)")

    # 2. VLM VERIFICATION VIA TRAJECTORY
    vlm_passed = False
    try:
        # Sample trajectory to ensure we catch the transient Lens tool UI
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        # In case the agent properly exported the file, we could also copy it locally
        # to feed to VLM, but using the robust trajectory frames prevents faking images.
        images_to_check = frames + [final] if final else frames

        prompt = (
            "You are evaluating an AI agent performing a visual task in Weasis DICOM viewer. "
            "The task requires activating the 'Lens' (magnifying glass) tool. "
            "Look closely at these trajectory frames. Do any of them show the Weasis Lens tool "
            "actively magnifying the image? The Lens tool usually appears as a distinct square or "
            "circular inset overlay following the cursor, showing a zoomed-in portion of the underlying pixels. "
            "\n\nRespond strictly in JSON format with two boolean fields: "
            "'weasis_visible' (is the Weasis UI open?) and 'lens_tool_active' (is the magnifier overlay visible?)."
        )

        vlm_response = query_vlm(images=images_to_check, prompt=prompt)

        if vlm_response and vlm_response.get("success"):
            parsed = vlm_response.get("parsed", {})
            weasis_visible = parsed.get("weasis_visible", False)
            lens_active = parsed.get("lens_tool_active", False)

            if lens_active:
                score += 50
                vlm_passed = True
                feedback_parts.append("VLM confirmed Lens tool active")
            elif weasis_visible:
                score += 10
                feedback_parts.append("VLM saw Weasis, but Lens tool was not active")
            else:
                feedback_parts.append("VLM did not detect Weasis UI")
        else:
            feedback_parts.append(f"VLM query failed: {vlm_response.get('error', 'unknown error')}")

    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        feedback_parts.append("VLM trajectory evaluation skipped/error")

    # OVERALL EVALUATION
    # Task requires the exact file to be created during the task, AND the VLM must confirm the tool was used.
    key_criteria_met = (output_exists and created_during and vlm_passed)
    passed = (score >= 80) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }