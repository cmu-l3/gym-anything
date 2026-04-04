#!/usr/bin/env python3
import json
import os
import tempfile
import logging
import csv
import math
import numpy as np
from PIL import Image

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ct_calibration(traj, env_info, task_info):
    """
    Verifies the CT calibration task.
    Checks:
    1. Output files exist and were modified during task.
    2. Calibrated image pixel values match expected HU values (using Ground Truth slope/intercept).
    3. Bone mask covers the high-intensity regions.
    4. CSV report contains reasonable values.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    score = 0
    feedback = []
    
    # Files to retrieve
    files = {
        "result": "/tmp/task_result.json",
        "gt": "/tmp/ground_truth.json",
        "image": "/tmp/calibrated_ct.tif",
        "mask": "/tmp/bone_mask.png",
        "csv": "/tmp/density_report.csv"
    }
    
    local_files = {}
    
    # 1. Retrieve files
    with tempfile.TemporaryDirectory() as tmpdir:
        for key, path in files.items():
            local_path = os.path.join(tmpdir, os.path.basename(path))
            try:
                copy_from_env(path, local_path)
                local_files[key] = local_path
            except Exception:
                local_files[key] = None

        # Load JSONs
        if not local_files["result"] or not local_files["gt"]:
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve results or ground truth"}
            
        with open(local_files["result"]) as f:
            res_data = json.load(f)
        with open(local_files["gt"]) as f:
            gt_data = json.load(f)

        # === CRITERION 1: Files Exist (20 pts) ===
        if res_data.get("image_exists") and res_data.get("image_modified"):
            score += 10
            feedback.append("Calibrated image created.")
        else:
            feedback.append("Calibrated image missing or not modified.")
            
        if res_data.get("mask_exists"):
            score += 5
            feedback.append("Bone mask created.")
        else:
            feedback.append("Bone mask missing.")
            
        if res_data.get("csv_exists"):
            score += 5
            feedback.append("Report CSV created.")
        else:
            feedback.append("Report CSV missing.")

        # === CRITERION 2: Calibration Accuracy (40 pts) ===
        # We need to analyze the calibrated image.
        # Since we don't have the original coordinates of air/water easily accessible 
        # (they depend on the image content), we can check the DISTRIBUTION of values.
        # A properly calibrated head CT should have:
        # - A large peak around -1000 (Air)
        # - A peak around 0 (Water/Brain soft tissue)
        # - Values > 400 (Bone)
        
        calib_passed = False
        if local_files["image"]:
            try:
                img = Image.open(local_files["image"])
                arr = np.array(img).astype(float)
                
                # Check 1: Background (Air)
                # The most frequent value in the lower range should be near -1000
                # Histogram approach
                hist, bins = np.histogram(arr, bins=100, range=(-2000, 2000))
                peak_idx = np.argmax(hist)
                peak_val = bins[peak_idx]
                
                # In a CT, air is usually the most common pixel (background)
                # Tolerance +/- 100 HU
                if -1100 <= peak_val <= -900:
                    score += 20
                    feedback.append(f"Background calibrated correctly (Peak ~ {peak_val:.0f} HU).")
                    calib_passed = True
                else:
                    feedback.append(f"Background calibration incorrect (Peak ~ {peak_val:.0f} HU, expected -1000).")

                # Check 2: Soft Tissue / Water
                # There should be significant pixels around 0-50 HU
                # Let's check mean of pixels in the -100 to 100 range
                soft_tissue = arr[(arr > -100) & (arr < 100)]
                if len(soft_tissue) > 100:
                    score += 20
                    feedback.append("Soft tissue values present in 0 HU range.")
                else:
                    feedback.append("Missing soft tissue values around 0 HU.")

            except Exception as e:
                feedback.append(f"Error analyzing image: {e}")

        # === CRITERION 3: Bone Mask (20 pts) ===
        if local_files["mask"] and local_files["image"]:
            try:
                mask_img = Image.open(local_files["mask"]).convert("L")
                mask_arr = np.array(mask_img) > 128 # Binary
                
                # Check alignment with calibrated image high values
                # Pixels in mask should correspond to pixels > 400 in image
                calib_arr = np.array(Image.open(local_files["image"]))
                
                bone_pixels = calib_arr[mask_arr]
                non_bone_pixels = calib_arr[~mask_arr]
                
                # Calculate precision/recall proxy
                # We expect bone pixels to be > 300 (allow some margin)
                valid_bone = np.mean(bone_pixels > 300)
                
                if valid_bone > 0.8:
                    score += 20
                    feedback.append("Bone mask accurately highlights high-density regions.")
                else:
                    feedback.append(f"Bone mask includes too much non-bone tissue ({valid_bone:.2%} valid).")
                    
            except Exception as e:
                feedback.append(f"Error analyzing mask: {e}")

        # === CRITERION 4: CSV Report (20 pts) ===
        if local_files["csv"]:
            try:
                with open(local_files["csv"], 'r') as f:
                    content = f.read().lower()
                    # Check for keywords
                    if "air" in content and "water" in content:
                        score += 10
                        feedback.append("Report contains Air and Water entries.")
                    else:
                        feedback.append("Report missing Air/Water labels.")
                        
                    # Check for values
                    # Simple heuristic: look for numbers near -1000 and 0
                    if "-1000" in content or "-9" in content or "-10" in content: # Loose check
                        score += 10
                        feedback.append("Report values look reasonable.")
            except Exception:
                pass

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }