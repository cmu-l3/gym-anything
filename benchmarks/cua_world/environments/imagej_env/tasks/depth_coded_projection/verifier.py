#!/usr/bin/env python3
"""
Verifier for depth_coded_projection task.

Checks:
1. Output file exists and is valid image.
2. Dimensions match Fly Brain (256x256).
3. Structural Similarity: Grayscale version matches Fly Brain structure.
4. Color Analysis: Image is RGB and has significant color.
5. Anti-Gaming: Verifies 'Depth Coding' vs 'Simple LUT'.
   - Depth Coding: Hue is uncorrelated with Intensity.
   - Simple LUT: Hue is highly correlated with Intensity.
"""

import json
import os
import tempfile
import logging
import numpy as np
from PIL import Image

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_depth_coded_projection(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Setup paths
    metadata = task_info.get('metadata', {})
    expected_output = metadata.get('expected_output_path', '/home/ga/ImageJ_Data/results/depth_coded_fly_brain.png')
    gt_path = metadata.get('ground_truth_mip_path', '/var/lib/imagej/ground_truth/fly_brain_mip.tif')

    score = 0
    feedback = []
    
    # ---------------------------------------------------------
    # 1. Retrieve Result JSON and Files
    # ---------------------------------------------------------
    with tempfile.TemporaryDirectory() as temp_dir:
        json_local = os.path.join(temp_dir, "result.json")
        img_local = os.path.join(temp_dir, "output.png")
        gt_local = os.path.join(temp_dir, "gt.tif")
        
        # Get JSON
        try:
            copy_from_env("/tmp/depth_coded_result.json", json_local)
            with open(json_local) as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task metadata: {str(e)}"}

        if not result_data.get("output_exists"):
            return {"passed": False, "score": 0, "feedback": "Output file not found."}
            
        if not result_data.get("created_during_task"):
            return {"passed": False, "score": 0, "feedback": "Output file exists but was not created during this task session."}
        
        score += 20 # File exists and is new
        
        # Get Images
        try:
            copy_from_env(expected_output, img_local)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": "Output file found but could not be downloaded."}

        has_gt = False
        try:
            copy_from_env(gt_path, gt_local)
            has_gt = True
        except Exception:
            logger.warning("Ground Truth file could not be retrieved. Skipping structural verification.")

        # ---------------------------------------------------------
        # 2. Image Analysis
        # ---------------------------------------------------------
        try:
            img = Image.open(img_local)
            img_arr = np.array(img)
            
            # Check Dimensions (256x256)
            if img.size != (256, 256):
                feedback.append(f"Incorrect dimensions: {img.size}, expected (256, 256).")
            else:
                score += 10
                feedback.append("Correct dimensions.")

            # Check RGB
            if img.mode != 'RGB' and len(img_arr.shape) != 3:
                return {"passed": False, "score": score, "feedback": "Output is not a color (RGB) image."}
            
            score += 10 # Is RGB
            
            # Check for "Black" or "Empty" image
            if np.mean(img_arr) < 5:
                return {"passed": False, "score": score, "feedback": "Image is nearly black/empty."}

            # ---------------------------------------------------------
            # 3. Structural Match (vs GT)
            # ---------------------------------------------------------
            if has_gt:
                try:
                    gt = Image.open(gt_local).convert('L')
                    gt_arr = np.array(gt)
                    
                    # Convert output to grayscale for structural comparison
                    out_gray = img.convert('L')
                    out_gray_arr = np.array(out_gray)
                    
                    # Normalize both
                    gt_norm = (gt_arr - np.mean(gt_arr)) / (np.std(gt_arr) + 1e-5)
                    out_norm = (out_gray_arr - np.mean(out_gray_arr)) / (np.std(out_gray_arr) + 1e-5)
                    
                    # Correlation
                    correlation = np.mean(gt_norm * out_norm)
                    
                    if correlation > 0.8:
                        score += 30
                        feedback.append("Structural match confirmed (looks like Fly Brain).")
                    else:
                        feedback.append(f"Structural mismatch (Correlation: {correlation:.2f}). Did you use the 'Fly Brain' sample?")
                except Exception as e:
                    logger.error(f"Structural check failed: {e}")
            else:
                # If GT missing, award points if image looks biological (non-uniform)
                if np.std(img_arr) > 20:
                    score += 30
                    feedback.append("Image structure assumed valid (GT missing).")

            # ---------------------------------------------------------
            # 4. Anti-Gaming: Depth Coding Check
            # ---------------------------------------------------------
            # Logic: In a Z-coded image, Hue is depth, Intensity is brightness.
            # In a simple LUT image, Hue is tied to Intensity (e.g. Fire LUT: bright=yellow, dim=red).
            
            # Convert to HSV
            img_hsv = img.convert('HSV')
            hsv_arr = np.array(img_hsv)
            H = hsv_arr[:,:,0].flatten()
            V = hsv_arr[:,:,2].flatten()
            
            # Filter out background (black) pixels to avoid skewing stats
            mask = V > 20
            if np.sum(mask) == 0:
                 return {"passed": False, "score": score, "feedback": "Image has no signal."}
                 
            H_vals = H[mask]
            V_vals = V[mask]
            
            # Calculate correlation between Hue and Value (Intensity)
            # Use absolute correlation because relationship could be inverse
            hv_corr = abs(np.corrcoef(H_vals, V_vals)[0, 1])
            
            # Check Color Variance (Saturation) to ensure it's not just grayscale
            S_mean = np.mean(hsv_arr[:,:,1][mask])
            
            if S_mean < 20:
                feedback.append("Image has very little color (mostly grayscale).")
            else:
                score += 10 # Has color
                
                # Z-Coded images should have LOW correlation between H and V
                # Simple LUT images have HIGH correlation
                if hv_corr < 0.6:
                    score += 20
                    feedback.append(f"Depth coding verified (Hue-Intensity correlation: {hv_corr:.2f}).")
                else:
                    feedback.append(f"Failed depth-coding check. Hue correlates with Intensity ({hv_corr:.2f}). Likely just applied a LUT to a 2D projection instead of using Temporal-Color Code.")

        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Image analysis failed: {str(e)}"}

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }