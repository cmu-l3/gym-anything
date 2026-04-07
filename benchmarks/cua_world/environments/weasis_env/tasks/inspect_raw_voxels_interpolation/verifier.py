#!/usr/bin/env python3
"""
Verifier for inspect_raw_voxels_interpolation task.

VERIFICATION STRATEGY:
1. File Verification: Check if `nearest_neighbor.png` was created after the task started.
2. Mathematical Blockiness Heuristic: The test uses a noisy image base where gradients ensure 
   virtually zero adjacent pixels are identical under standard "Bilinear" interpolation.
   If "Nearest" interpolation is applied alongside a >400% zoom, 1 image voxel stretches
   to a 4x4+ block of identical screen pixels. We verify this by computing the absolute difference 
   between adjacent image pixels. If >25% of adjacent pixel pairs are identical (diff == 0), 
   the image is mathematically proven to be blocky (zoomed + nearest neighbor).
3. VLM Workflow Verification: Validates navigation to Interpolation menus in trajectory.
"""

import os
import json
import logging
import tempfile
import numpy as np
from PIL import Image

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_inspect_raw_voxels(traj, env_info, task_info):
    """
    Verify that the user zoomed in and changed interpolation to Nearest Neighbor.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/DICOM/exports/nearest_neighbor.png')
    min_identical_ratio = metadata.get('min_identical_ratio', 0.25)

    feedback_parts = []
    score = 0
    heuristic_passed = False

    # Read result from export script
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

    # Criterion 1 & 2: Output file exists and was created during task
    output_exists = result.get('output_exists', False)
    created_during = result.get('file_created_during_task', False)
    
    if output_exists:
        score += 10
        feedback_parts.append("Export file found")
        if created_during:
            score += 10
            feedback_parts.append("File created during task")
        else:
            feedback_parts.append("Warning: File created before task started")
    else:
        feedback_parts.append("Export file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 3: Blockiness Heuristic (The core check)
    temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        copy_from_env(expected_output_path, temp_img.name)
        
        # Load image and convert to grayscale matrix
        img = Image.open(temp_img.name).convert('L')
        img_arr = np.array(img, dtype=np.int32)
        
        # Determine foreground mask to ignore pure black background UI/canvas regions
        fg_mask = img_arr > 10
        
        # Compute horizontal differences
        diff_x = np.abs(img_arr[:, 1:] - img_arr[:, :-1])
        fg_pairs_x = fg_mask[:, 1:] & fg_mask[:, :-1]
        identical_x = (diff_x == 0) & fg_pairs_x
        
        # Compute vertical differences
        diff_y = np.abs(img_arr[1:, :] - img_arr[:-1, :])
        fg_pairs_y = fg_mask[1:, :] & fg_mask[:-1, :]
        identical_y = (diff_y == 0) & fg_pairs_y
        
        total_fg_pairs = np.sum(fg_pairs_x) + np.sum(fg_pairs_y)
        total_identical = np.sum(identical_x) + np.sum(identical_y)
        
        ratio = float(total_identical) / float(total_fg_pairs) if total_fg_pairs > 0 else 0.0
        
        logger.info(f"Blockiness Heuristic: {total_identical} identical / {total_fg_pairs} total fg pairs = {ratio:.3f}")
        
        if total_fg_pairs < 5000:
            feedback_parts.append("Insufficient foreground data (empty or too small image)")
            heuristic_passed = False
        elif ratio >= min_identical_ratio:
            score += 60
            feedback_parts.append(f"Image is highly blocky (ratio: {ratio:.2f} >= {min_identical_ratio})")
            heuristic_passed = True
        else:
            feedback_parts.append(f"Image is smooth, Nearest+Zoom not detected (ratio: {ratio:.2f} < {min_identical_ratio})")
            heuristic_passed = False
            
    except Exception as e:
        logger.error(f"Failed to analyze image: {e}")
        feedback_parts.append("Image analysis failed")
        heuristic_passed = False
    finally:
        if os.path.exists(temp_img.name):
            os.unlink(temp_img.name)

    # VLM Verification (Optional fallback/supplement using trajectory frames)
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        
        images = frames + [final_frame] if final_frame else frames
        if images:
            prompt = (
                "You are evaluating an agent using Weasis DICOM Viewer. "
                "The task is to deeply zoom into the image and change the display Interpolation to 'Nearest' (Nearest Neighbor). "
                "Look at these chronological trajectory screenshots. "
                "1. Did the agent navigate a menu/toolbar to change Interpolation settings? "
                "2. Does the final image appear deeply zoomed in and distinctly pixelated/blocky? "
                "Respond in JSON format: {\"menu_accessed\": true/false, \"is_zoomed_and_blocky\": true/false}"
            )
            
            vlm_result = query_vlm(images=images, prompt=prompt)
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("menu_accessed", False):
                    vlm_score += 10
                    feedback_parts.append("VLM: Menu accessed")
                if parsed.get("is_zoomed_and_blocky", False):
                    vlm_score += 10
                    feedback_parts.append("VLM: Zoomed and blocky confirmed")
            else:
                logger.warning(f"VLM query failed: {vlm_result.get('error', 'unknown')}")
                if heuristic_passed: vlm_score += 20
        else:
            if heuristic_passed: vlm_score += 20
    except ImportError:
        logger.warning("VLM tools not available. Skipping VLM check.")
        if heuristic_passed: vlm_score += 20
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        if heuristic_passed: vlm_score += 20
            
    score += vlm_score

    # Final pass logic: Only pass if the robust blockiness mathematical test was passed
    passed = (score >= 70) and heuristic_passed

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }