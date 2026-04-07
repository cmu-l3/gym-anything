#!/usr/bin/env python3
"""
Verifier for create_hubble_palette_composite task.

Verification Strategy:
1. Programmatic metrics via exported JSON (File existence, Timestamp, Format, Stretch/Mean, Color diversity/StdDev)
2. Trajectory VLM check to verify workflow execution.
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_hubble_palette(traj, env_info, task_info):
    """Verifies that the agent correctly combined the FITS files into an RGB composite."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_mean = metadata.get('min_mean_intensity', 10.0)
    max_mean = metadata.get('max_mean_intensity', 250.0)
    min_channel_std = metadata.get('min_channel_std', 5.0)

    # 1. Load exported result statistics
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
    
    output_exists = result.get('output_exists', False)
    created_during_task = result.get('created_during_task', False)
    is_rgb = result.get('is_rgb', False)
    mean_intensity = result.get('mean_intensity', 0.0)
    std_rg = result.get('std_rg', 0.0)
    std_gb = result.get('std_gb', 0.0)
    std_rb = result.get('std_rb', 0.0)

    # Calculate average standard deviation across channels
    avg_channel_std = (std_rg + std_gb + std_rb) / 3.0

    # Criterion 1: File Exists (10 pts)
    if output_exists:
        score += 10
        feedback_parts.append("Output file exists")
        
        # Criterion 2: Created During Task (10 pts)
        if created_during_task:
            score += 10
            feedback_parts.append("File created during session")
        else:
            feedback_parts.append("File modified timestamp predates task start")

        # Criterion 3: RGB Format (20 pts)
        if is_rgb:
            score += 20
            feedback_parts.append("Format is valid RGB")
        else:
            feedback_parts.append("Image is not RGB/RGBA")

        # Criterion 4: Stretch / Content Visibility (20 pts)
        if min_mean < mean_intensity < max_mean:
            score += 20
            feedback_parts.append(f"Properly stretched (mean: {mean_intensity:.1f})")
        else:
            feedback_parts.append(f"Improper stretch / blank image (mean: {mean_intensity:.1f})")

        # Criterion 5: Channel Diversity / True Color (20 pts)
        if avg_channel_std > min_channel_std:
            score += 20
            feedback_parts.append(f"Distinct color channels (std: {avg_channel_std:.1f})")
        else:
            feedback_parts.append(f"Channels too similar/monochrome (std: {avg_channel_std:.1f})")

    else:
        feedback_parts.append("Output file missing")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": " | ".join(feedback_parts)
        }

    # Criterion 6: VLM Verification (20 pts)
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        
        prompt = (
            "You are verifying an AstroImageJ workflow for astronomical image processing.\n"
            "Task: The user must open three FITS images of the Eagle Nebula, stretch their histograms "
            "to reveal nebula structures, and use the 'Merge Channels' or 'Color' tool to combine them "
            "into a Hubble Palette (RGB) composite.\n\n"
            "Review the trajectory. Did the agent open the astronomical images, interact with the contrast/brightness "
            "tools to make them visible, and successfully merge them into a colored composite? "
            "Respond strictly with 'YES' or 'NO'."
        )
        
        vlm_response = query_vlm(images=frames + [final_frame], prompt=prompt)
        
        if "YES" in vlm_response.upper():
            score += 20
            feedback_parts.append("VLM verified visual workflow")
        else:
            feedback_parts.append("VLM could not verify proper workflow execution")
            
    except Exception as e:
        logger.error(f"VLM check failed: {e}")
        feedback_parts.append(f"VLM error: {str(e)[:50]}")

    # Pass threshold: must meet all major programmatic criteria (Score >= 80)
    key_criteria_met = output_exists and created_during_task and is_rgb and (min_mean < mean_intensity < max_mean) and (avg_channel_std > min_channel_std)
    passed = score >= 80 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }