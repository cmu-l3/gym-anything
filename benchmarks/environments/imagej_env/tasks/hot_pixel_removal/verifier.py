#!/usr/bin/env python3
"""
Verifier for Hot Pixel Removal task.

Verification Logic:
1. File Existence & Validity (20 pts)
   - Output file exists, is 16-bit TIFF, created during task.
2. Hot Pixel Removal (40 pts)
   - The number of pixels with max intensity (approx 65535) should be near zero.
   - Input had ~300. Output should have < 10.
3. Detail Preservation (20 pts)
   - Image should not be excessively blurry.
   - We check the Laplacian variance ratio vs Ground Truth.
   - If ratio < 0.5, likely a strong Gaussian blur was used (bad).
   - If ratio > 0.8, sharpness is well preserved.
4. Data Fidelity (20 pts)
   - MSE against Ground Truth should be low.
   - Checks that the agent didn't just output a black image or the original noisy image.

Pass Threshold: 80 points
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hot_pixel_removal(traj, env_info, task_info):
    """
    Verify the hot pixel removal task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load JSON result calculated by export_result.sh
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/hot_pixel_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract metrics
    file_exists = result.get("file_exists", False)
    created_during_task = result.get("file_created_during_task", False)
    hot_pixel_count = result.get("hot_pixel_count", 9999)
    input_hot_pixels = result.get("input_hot_pixel_count", 300)
    mse = result.get("mse_vs_gt", 999999.0)
    blur_ratio = result.get("blurriness_ratio", 0.0)
    error = result.get("error")

    score = 0
    feedback = []

    # Criterion 1: File Validity (20 pts)
    if file_exists and created_during_task:
        score += 20
        feedback.append("Output file created successfully.")
    elif file_exists:
        score += 10
        feedback.append("Output file exists but timestamp suggests pre-existence.")
    else:
        feedback.append("Output file not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: Hot Pixel Removal (40 pts)
    # We expect near 0 hot pixels. Allow small margin for edge cases.
    if hot_pixel_count < 5:
        score += 40
        feedback.append(f"Hot pixels successfully removed (count: {hot_pixel_count}).")
    elif hot_pixel_count < 50:
        score += 20
        feedback.append(f"Some hot pixels remaining (count: {hot_pixel_count}).")
    else:
        feedback.append(f"Hot pixels still present (count: {hot_pixel_count}). Input had {input_hot_pixels}.")

    # Criterion 3: Detail Preservation (Blurriness) (20 pts)
    # If they just blurred the image, this ratio will be low.
    # Process > Noise > Remove Outliers usually preserves edges well (ratio ~0.9-1.0).
    if blur_ratio > 0.8:
        score += 20
        feedback.append("Image sharpness well preserved.")
    elif blur_ratio > 0.5:
        score += 10
        feedback.append("Image is somewhat blurred.")
    else:
        feedback.append(f"Image is excessively blurred (ratio: {blur_ratio:.2f}). Did you use Gaussian Blur instead of Remove Outliers?")

    # Criterion 4: Data Fidelity (MSE) (20 pts)
    # If they output a black image, MSE will be high (galaxy signal missing).
    # If they output original noisy image, MSE will be high (due to hot pixels).
    # Threshold depends on image range. 16-bit images have high values.
    # Clean restoration MSE should be low.
    # Note: MSE of noisy vs gt is roughly (300 * 65535^2) / (512*512) -> very high.
    # We check if MSE is 'reasonable' compared to the signal.
    # Let's rely on a relative check: Is it better than the input?
    # Actually, simplistic black image check:
    if mse < 1000.0: # Arbitrary threshold for good restoration
        score += 20
        feedback.append("Restoration quality is high (low MSE).")
    elif mse < 10000.0:
        score += 10
        feedback.append("Restoration quality is acceptable.")
    else:
        feedback.append(f"High error vs ground truth (MSE: {mse:.0f}).")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result
    }