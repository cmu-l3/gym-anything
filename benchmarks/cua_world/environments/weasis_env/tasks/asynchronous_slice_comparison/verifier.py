#!/usr/bin/env python3
"""Verifier for asynchronous_slice_comparison task."""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_asynchronous_slice_comparison(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
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

    score = 0
    feedback_parts = []
    
    # 1. File checks - Detect gaming via timestamp validation
    files_ok = False
    if result.get("screenshot_exists") and result.get("text_exists"):
        if result.get("screenshot_created_during_task") and result.get("text_created_during_task"):
            if result.get("text_correct"):
                score += 10
                files_ok = True
                feedback_parts.append("Export files created correctly")
            else:
                feedback_parts.append("Text file exists but content incorrect")
        else:
            feedback_parts.append("Files exist but not created during task (gaming detected)")
    else:
        feedback_parts.append("Required export files missing")

    # 2. VLM Verification - Trajectory preferred over final screen to prevent forged final states
    images_to_check = []
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        if frames:
            images_to_check.extend(frames)
        if final:
            images_to_check.append(final)
    except ImportError:
        logger.warning("Could not import gym_anything.vlm")

    # If framework didn't provide trajectory frames, attempt to extract the agent's explicit screenshot
    if not images_to_check and result.get("screenshot_exists"):
        try:
            agent_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env("/home/ga/DICOM/exports/async_comparison.png", agent_screenshot.name)
            images_to_check = [agent_screenshot.name]
        except Exception as e:
            logger.warning(f"Could not copy agent screenshot: {e}")

    prompt = """You are analyzing screenshots of a Weasis DICOM Viewer task.
The user's goal was to configure a 1x2 side-by-side layout, load the SAME CT series in both panes, and disable scrolling synchronization to show DIFFERENT slices in the two panes.

Looking at the sequence of screenshots, please verify the following in any of the later frames:
1. is_1x2_layout: Is there a 1x2 (side-by-side) split viewport layout visible?
2. is_same_series: Do both panes display the same CT series? (Look for matching patient/series metadata text in the corners of both panes)
3. is_sync_disabled: Are the two panes displaying DIFFERENT slices? (Look at the "Image: X/Y" or "Img: X" text in the corners, or visually check if the anatomy/circle position is distinctly different between the two panes).

Respond ONLY in valid JSON format:
{
    "is_1x2_layout": true/false,
    "is_same_series": true/false,
    "is_sync_disabled": true/false,
    "reasoning": "brief explanation"
}
"""

    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        feedback_parts.append("VLM not available")
    elif not images_to_check:
        feedback_parts.append("No images available for VLM")
    else:
        vlm_res = query_vlm(images=images_to_check, prompt=prompt)
        if vlm_res and vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            
            is_1x2 = parsed.get("is_1x2_layout", False)
            is_same = parsed.get("is_same_series", False)
            is_async = parsed.get("is_sync_disabled", False)
            
            if is_1x2:
                score += 20
                feedback_parts.append("1x2 layout detected")
            else:
                feedback_parts.append("1x2 layout NOT detected")
                
            if is_same:
                score += 30
                feedback_parts.append("Same series in both panes")
            else:
                feedback_parts.append("Not displaying same series")
                
            if is_async:
                score += 40
                feedback_parts.append("Sync disabled (different slices)")
            else:
                feedback_parts.append("Slices are identical (sync likely still enabled)")
                
        else:
            feedback_parts.append("VLM query failed")

    # Pass requires both file existence AND successful completion of the core async UI actions
    passed = score >= 70 and files_ok
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }