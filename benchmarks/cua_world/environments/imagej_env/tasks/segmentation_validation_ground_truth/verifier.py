#!/usr/bin/env python3
"""
Verifier for segmentation_validation_ground_truth task.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_segmentation_validation(traj, env_info, task_info):
    """
    Verify the segmentation validation workflow.
    
    Success Criteria:
    1. Difference image exists and was created during task.
    2. Difference image content is valid (Mean intensity > 0.1 and < 50).
       - 0 means blank/perfect (suspicious).
       - >50 means inputs were totally different or not thresholded.
    3. Metrics CSV exists and contains measurement data.
    4. VLM verifies 'Image Calculator' or 'Difference' workflow.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # --- Criterion 1: Files Exist & Timestamp (30 pts) ---
    if result.get("diff_image_exists") and result.get("metrics_file_exists"):
        if result.get("file_created_during_task"):
            score += 30
            feedback.append("Output files created successfully.")
        else:
            score += 10
            feedback.append("Output files exist but timestamp is old (pre-existing?).")
    else:
        feedback.append("Missing one or more output files.")

    # --- Criterion 2: Difference Image Validity (40 pts) ---
    mean_val = result.get("diff_mean_intensity", -1)
    is_binary = result.get("diff_is_binary", False)
    
    if mean_val > 0:
        if 0.1 < mean_val < 60.0:
            score += 40
            feedback.append(f"Difference image indicates valid segmentation comparison (Mean error: {mean_val:.2f}).")
        elif mean_val <= 0.1:
            # Suspiciously perfect
            score += 10
            feedback.append("Difference image is nearly blank/black (Mean ~ 0). Segmentation should not be perfectly identical to ground truth unless copied.")
        else:
            # Too high error
            score += 15
            feedback.append(f"Difference image shows very high error (Mean: {mean_val:.2f}). Did you compare the correct images?")
    else:
        feedback.append("Invalid or unreadable difference image.")

    # --- Criterion 3: VLM Workflow Check (30 pts) ---
    # We want to see 'Image Calculator' usage or two images being processed
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    
    vlm_prompt = """
    Check if the user is performing image validation/comparison in ImageJ.
    Look for:
    1. 'Image Calculator' window/dialog.
    2. Two image windows open (Raw and Ground Truth).
    3. A resulting window (often called 'Result of...' or showing black/white differences).
    4. Measurement Results table.
    
    Did the user perform an image calculation/comparison?
    """
    
    vlm_result = query_vlm(images=frames + [final], prompt=vlm_prompt)
    
    vlm_passed = False
    if "yes" in vlm_result.get("response", "").lower() or "calculated" in vlm_result.get("response", "").lower() or "comparison" in vlm_result.get("response", "").lower():
        vlm_passed = True
        score += 30
        feedback.append("VLM confirmed image calculation workflow.")
    else:
        # Fallback partial credit if we have strong file evidence
        if score >= 60:
            score += 10
            feedback.append("VLM did not clearly see workflow, but outputs are strong.")
        else:
            feedback.append("VLM did not verify image comparison workflow.")

    # Final Pass/Fail
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }