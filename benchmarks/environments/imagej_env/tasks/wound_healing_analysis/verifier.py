#!/usr/bin/env python3
"""
Verifier for Wound Healing Analysis.

Scoring Criteria:
1. Files Exist & Valid Timestamps (20 pts)
2. Mask is Binary (0/255) (10 pts)
3. CSV Area matches Mask Area (20 pts)
4. Segmentation Quality (Texture Ratio) (30 pts)
   - Checks if 'wound' region (mask=255) is smoother than 'cell' region (mask=0)
   - Using the actual original image pixels
5. Topology / Sanity Check (20 pts)
   - Mask is not empty/full
   - Mask is not just noise (salt & pepper)
"""

import json
import os
import sys
import tempfile
import logging
import math
import shutil

# Try to import numeric libraries; they should be in the host env
try:
    import numpy as np
    import pandas as pd
    from skimage import io, measure, filters
    from skimage.color import rgb2gray
except ImportError:
    logging.warning("Required libraries (numpy, pandas, skimage) not found.")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_wound_healing(traj, env_info, task_info):
    """
    Verify the wound healing analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Setup temp directory for analysis
    temp_dir = tempfile.mkdtemp()
    
    score = 0
    feedback = []
    
    try:
        # 1. Retrieve JSON summary
        local_json = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/tmp/task_result.json", local_json)
            with open(local_json, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not retrieve task result: {str(e)}"}

        task_start = result.get('task_start', 0)
        mask_path = result.get('mask_image_path', '')
        csv_path = result.get('csv_path', '')
        raw_path = result.get('original_image_path', '')

        # 2. Check File Existence & Timestamp (20 pts)
        files_ok = True
        
        # Check Mask
        if not result.get('mask_exists'):
            feedback.append("FAIL: Mask file not found.")
            files_ok = False
        elif result.get('mask_timestamp', 0) <= task_start:
            feedback.append("FAIL: Mask file is older than task start (pre-existing?).")
            files_ok = False
            
        # Check CSV
        if not result.get('csv_exists'):
            feedback.append("FAIL: Results CSV not found.")
            files_ok = False
        elif result.get('csv_timestamp', 0) <= task_start:
            feedback.append("FAIL: CSV file is older than task start.")
            files_ok = False
            
        if files_ok:
            score += 20
            feedback.append("Files created successfully.")
        else:
            # Critical fail if files don't exist
            return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

        # 3. Retrieve Actual Files for Content Analysis
        local_mask = os.path.join(temp_dir, "mask.tif")
        local_csv = os.path.join(temp_dir, "results.csv")
        local_raw = os.path.join(temp_dir, "raw.tif")
        
        try:
            copy_from_env(mask_path, local_mask)
            copy_from_env(csv_path, local_csv)
            copy_from_env(raw_path, local_raw)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to download result files for analysis: {e}"}

        # Load images
        try:
            mask_img = io.imread(local_mask)
            raw_img = io.imread(local_raw)
            
            # Handle dimensions/channels
            if mask_img.ndim > 2:
                mask_img = mask_img[:,:,0] # Take first channel if RGB
            if raw_img.ndim > 2:
                raw_img = rgb2gray(raw_img) # Convert raw to gray if RGB
                
            # Resize mask if dimensions don't match (e.g. if agent cropped or resized)
            if mask_img.shape != raw_img.shape:
                feedback.append(f"Warning: Mask dimensions {mask_img.shape} differ from raw {raw_img.shape}. Resizing for analysis.")
                from skimage.transform import resize
                mask_img = resize(mask_img, raw_img.shape, preserve_range=True, order=0).astype(np.uint8)
                
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to open image files: {e}"}

        # 4. Verify Mask is Binary (10 pts)
        unique_vals = np.unique(mask_img)
        is_binary = np.all(np.isin(unique_vals, [0, 255]))
        
        # Allow slight compression artifacts (e.g. 1, 254) but strictly it should be 0/255
        # If strict binary fails, check if it's effectively binary (>2 values is bad)
        if is_binary:
            score += 10
            feedback.append("Mask is strictly binary (0/255).")
        elif len(unique_vals) <= 2:
            score += 10
            feedback.append("Mask is binary but values are not 0/255 (acceptable).")
            # Normalize to 0/255 for later steps
            mask_img = (mask_img > mask_img.min()).astype(np.uint8) * 255
        else:
            feedback.append(f"Mask is not binary (contains {len(unique_vals)} unique values). Thresholding for further analysis.")
            # Binarize for further checks (Otsu)
            thresh = filters.threshold_otsu(mask_img)
            mask_img = (mask_img > thresh).astype(np.uint8) * 255

        # 5. Verify Area Consistency (20 pts)
        # Parse CSV
        try:
            df = pd.read_csv(local_csv)
            # Find Area column (flexible matching)
            area_col = next((c for c in df.columns if 'area' in c.lower()), None)
            
            if area_col:
                reported_area = float(df[area_col].iloc[0])
                measured_area = np.sum(mask_img > 128) # Count white pixels
                
                # Tolerance: 5%
                if abs(reported_area - measured_area) < (max(measured_area, 1) * 0.05) + 10:
                    score += 20
                    feedback.append(f"Reported Area ({reported_area}) matches Mask Area ({measured_area}).")
                else:
                    feedback.append(f"Area mismatch: Reported {reported_area} vs Mask {measured_area}.")
            else:
                feedback.append("CSV missing 'Area' column.")
        except Exception as e:
            feedback.append(f"Failed to parse CSV: {e}")

        # 6. Segmentation Quality (Texture Ratio) (30 pts)
        # In phase contrast, cells are textured (high std dev), wound is smooth (low std dev).
        # Mask: 255 should be wound, 0 should be cells.
        
        wound_mask = mask_img > 128
        cells_mask = mask_img <= 128
        
        # Check that mask isn't empty or full
        total_pixels = mask_img.size
        wound_pixels = np.sum(wound_mask)
        
        if wound_pixels < 0.01 * total_pixels or wound_pixels > 0.99 * total_pixels:
            feedback.append("Segmentation Failed: Mask is either empty or covers entire image.")
        else:
            # Calculate texture (Std Dev) in both regions
            # Use raw image intensities
            
            # Normalize raw image to 0-1 for stability
            raw_norm = (raw_img - raw_img.min()) / (raw_img.max() - raw_img.min() + 1e-6)
            
            std_wound = np.std(raw_norm[wound_mask])
            std_cells = np.std(raw_norm[cells_mask])
            
            # Avoid divide by zero
            std_wound = max(std_wound, 1e-6)
            
            # Ratio: Cells should be more textured than Wound
            ratio = std_cells / std_wound
            
            feedback.append(f"Texture Analysis: Cell_Std={std_cells:.3f}, Wound_Std={std_wound:.3f}, Ratio={ratio:.2f}")
            
            if ratio > 1.2:
                score += 30
                feedback.append("Segmentation Quality: Good (Cells clearly more textured than wound).")
            elif ratio > 1.05:
                score += 15
                feedback.append("Segmentation Quality: Marginal (Slight texture difference).")
            elif ratio < 1.0:
                # Inverted mask? (Wound is textured?)
                # If inverted, ratio would be < 1. Check if ratio < 0.8
                if ratio < 0.8:
                    feedback.append("Segmentation appears inverted (Wound labeled as cells?).")
                else:
                    feedback.append("Segmentation Quality: Poor (No texture distinction).")
            else:
                feedback.append("Segmentation Quality: Poor.")

        # 7. Topology Check (20 pts)
        # Wound should be 1-3 large regions, not 1000 speckles
        labeled_wound, num_features = measure.label(wound_mask, return_num=True)
        
        if 1 <= num_features <= 10:
            score += 20
            feedback.append(f"Topology Good: Found {num_features} wound regions.")
        elif num_features > 10:
            # Penalize noisy masks
            score += 5
            feedback.append(f"Topology Noisy: Found {num_features} regions. Despeckling needed.")
        else:
            feedback.append("Topology Bad: No regions found.")

    except Exception as e:
        import traceback
        feedback.append(f"Verification crashed: {str(e)}")
        logger.error(traceback.format_exc())
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }