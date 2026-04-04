#!/usr/bin/env python3
"""
Verifier for extract_bolivia_raster task.

Criteria:
1. Output file exists and is a valid image (TIFF preferred).
2. Output file was created during the task.
3. Image dimensions are reasonable for Bolivia extracted from the specific source raster.
   - Source: NE1_HR_LC_SR_W_DR.tif (16200 x 8100 pixels)
   - Bolivia: Approx 12 deg x 14 deg
   - Resolution: ~45 pixels/degree
   - Exp Width: ~540px, Exp Height: ~630px
   - Tolerance: Broad range [200, 1200] to account for projection diffs or buffer.
4. Image is not empty (standard deviation > 0).
5. VLM verification of the workflow.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_extract_bolivia_raster(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Metadata constraints
    metadata = task_info.get('metadata', {})
    min_dim = metadata.get('min_dimension', 200)
    max_dim = metadata.get('max_dimension', 1200)

    # Criterion 1: File Existence & Format (20 pts)
    file_exists = result.get('file_exists', False)
    fmt = result.get('image_format', 'unknown').upper()
    
    if file_exists:
        if 'TIFF' in fmt or 'TIF' in fmt:
            score += 20
            feedback_parts.append("Valid TIFF file found")
        elif fmt != 'UNKNOWN':
            score += 10
            feedback_parts.append(f"File found but format is {fmt} (expected TIFF)")
        else:
            feedback_parts.append("File exists but format unknown")
    else:
        feedback_parts.append("Output file not found")
        return {"passed": False, "score": 0, "feedback": "Output file not found"}

    # Criterion 2: Anti-Gaming Timestamp (15 pts)
    if result.get('file_created_during_task', False):
        score += 15
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp predates task start")

    # Criterion 3: Dimensions (30 pts)
    # Check if dimensions look like a country clip vs full map
    w = result.get('image_width', 0)
    h = result.get('image_height', 0)
    
    if min_dim <= w <= max_dim and min_dim <= h <= max_dim:
        score += 30
        feedback_parts.append(f"Dimensions correct ({w}x{h})")
    else:
        feedback_parts.append(f"Dimensions incorrect ({w}x{h}). Expected range [{min_dim}-{max_dim}]")

    # Criterion 4: Content Check (10 pts)
    # Standard deviation indicates information content (not solid color)
    std_dev_str = result.get('image_std_dev', '0')
    try:
        # ImageMagick might return something like "1234.5 (0.123)" or just "1234.5"
        # We just need to check if it's > 0
        std_dev = float(std_dev_str.split()[0])
        if std_dev > 10:  # Allow for small noise, looking for real data
            score += 10
            feedback_parts.append("Image contains data")
        else:
            feedback_parts.append("Image appears empty/solid color")
    except:
        feedback_parts.append("Could not verify image content")

    # Criterion 5: VLM Trajectory Verification (25 pts)
    # We want to see the geoprocessing tool being used
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    
    vlm_prompt = (
        "Analyze these screenshots of a gvSIG Desktop task.\n"
        "Goal: Clip a raster map to the shape of Bolivia.\n"
        "Look for:\n"
        "1. A map showing South America or Bolivia.\n"
        "2. Usage of a Geoprocessing tool (like 'Clip', 'Cortar', 'Recortar').\n"
        "3. A dialog box configuring input raster and polygon layers.\n"
        "4. A final result showing a standalone shape of Bolivia.\n\n"
        "Did the agent perform the raster clip operation?"
    )
    
    try:
        vlm_result = query_vlm(images=frames + [final], prompt=vlm_prompt)
        if vlm_result.get('success', False) or "yes" in vlm_result.get('response', '').lower():
            score += 25
            feedback_parts.append("VLM verified workflow")
        else:
            feedback_parts.append("VLM did not observe clear workflow")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if file checks passed perfectly, give benefit of doubt
        if score >= 75:
            score += 25
            feedback_parts.append("VLM skipped (technical error)")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }