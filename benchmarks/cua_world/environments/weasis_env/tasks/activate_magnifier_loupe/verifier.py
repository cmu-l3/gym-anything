#!/usr/bin/env python3
"""
Verifier for Activate Magnifier (Loupe) Tool task.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Prompt explicitly targeting the unique visual nature of a Loupe tool
VLM_PROMPT = """You are evaluating a screenshot of the Weasis medical DICOM viewer.

The agent was instructed to activate the "Lens" or "Magnifier" tool (often called a Loupe) and capture a screenshot while it is active.

A Loupe tool is visually distinct from just zooming in on an image. When active:
1. Most of the application viewer shows the medical image at a normal zoom level.
2. There is a distinct INSET WIDGET (a hovering square or circular box with a border).
3. Inside this inset box, a highly magnified portion of the underlying image is shown.
4. Sometimes there's a crosshair or cursor at the center of the magnification box.

Examine the provided image(s) and determine:
1. Is the Weasis application visible?
2. Is the localized Lens/Magnifier/Loupe WIDGET actively visible on top of the image? (Do NOT say yes if the entire image is simply zoomed in globally; it MUST be a localized inset widget).

Respond in strict JSON format:
{
    "weasis_visible": true/false,
    "lens_widget_visible": true/false,
    "reasoning": "Briefly describe what you see, explicitly mentioning if an inset magnification box is present or just global zoom."
}
"""

def verify_activate_magnifier(traj, env_info, task_info):
    """
    Verify the magnifier was activated and captured.
    Uses multi-criteria anti-gaming:
    1. Output file exists and was created during the task (not pre-existing).
    2. File size is non-trivial.
    3. VLM verifies the trajectory frames and exported image contain the actual localized Lens widget.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available."}

    # 1. READ RESULT DATA
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Check expected metadata parameters
    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/DICOM/exports/lens_active.png')
    min_size = metadata.get('min_file_size_bytes', 15000)

    # 2. EVALUATE FILE CRITERIA (40 points total)
    file_valid = False
    if result.get('output_exists'):
        if result.get('file_created_during_task'):
            if result.get('output_size_bytes', 0) >= min_size:
                score += 20
                file_valid = True
                feedback_parts.append("Target screenshot successfully captured.")
            else:
                feedback_parts.append(f"Exported file too small ({result.get('output_size_bytes')} bytes).")
        else:
            feedback_parts.append("Exported file was not created during this task session (Timestamp mismatch).")
    else:
        feedback_parts.append("Expected screenshot file was not found.")

    # 3. VLM VISUAL VERIFICATION (60 points total)
    weasis_visible = False
    lens_visible = False

    # Try importing framework VLM helpers if available to get images
    images_to_check = []
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        # We sample a few frames plus the final frame, in case the agent captured the 
        # file but the final frame doesn't show it (e.g. they let go of the mouse).
        frames = sample_trajectory_frames(traj, n=3)
        final_frame = get_final_screenshot(traj)
        if frames:
            images_to_check.extend(frames)
        if final_frame:
            images_to_check.append(final_frame)
    except ImportError:
        # Fallback to manual trajectory inspection if helper is absent
        if traj and len(traj) > 0:
            if 'observation' in traj[-1] and 'image' in traj[-1]['observation']:
                images_to_check.append(traj[-1]['observation']['image'])

    if query_vlm and images_to_check:
        try:
            vlm_response = query_vlm(images=images_to_check, prompt=VLM_PROMPT)
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                weasis_visible = parsed.get("weasis_visible", False)
                lens_visible = parsed.get("lens_widget_visible", False)
                vlm_reasoning = parsed.get("reasoning", "")
                
                if weasis_visible:
                    score += 20
                    feedback_parts.append("VLM confirmed Weasis UI is present.")
                
                if lens_visible:
                    score += 60
                    feedback_parts.append("VLM confirmed active localized Lens widget.")
                else:
                    feedback_parts.append("VLM failed to detect the localized Lens widget (did you just global zoom?).")
                
                logger.info(f"VLM Reasoning: {vlm_reasoning}")
            else:
                feedback_parts.append("VLM query failed or returned no data.")
        except Exception as e:
            logger.error(f"VLM exception: {e}")
            feedback_parts.append("VLM exception during verification.")
    else:
        feedback_parts.append("VLM query tool or trajectory images not available.")

    # 4. FINAL DECISION
    # Agent must have captured the file AND VLM must detect the widget.
    passed = (score >= 80) and file_valid and lens_visible

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }