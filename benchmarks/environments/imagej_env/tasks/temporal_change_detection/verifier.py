#!/usr/bin/env python3
"""
Verifier for Temporal Change Detection task.
Verifies that the agent correctly processed the Mitosis stack to detect changes.
"""

import json
import os
import tempfile
import logging
import numpy as np
from PIL import Image

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_temporal_change(traj, env_info, task_info):
    """
    Verify the temporal change detection task.
    
    Criteria:
    1. Files exist: spindle_start.tif, spindle_end.tif, change_map.tif (30 pts)
    2. Files created during task (Timestamp check) (10 pts)
    3. Image Content Logic: abs(Start - End) approx equals ChangeMap (40 pts)
    4. Quantification: CSV exists and contains valid Area measurement (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/temporal_change_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    files_found = result_data.get("files_found", {})
    
    # 1. File Existence & 2. Timestamps
    expected_images = ["spindle_start.tif", "spindle_end.tif", "change_map.tif"]
    images_exist = True
    
    for img_name in expected_images:
        info = files_found.get(img_name, {})
        if info.get("exists"):
            score += 10
            if not info.get("valid_time"):
                feedback.append(f"Warning: {img_name} created before task start.")
                score -= 5 # Penalty for anti-gaming violation
        else:
            feedback.append(f"Missing file: {img_name}")
            images_exist = False

    csv_info = files_found.get("change_quantification.csv", {})
    if csv_info.get("exists"):
        score += 10
    else:
        feedback.append("Missing quantification CSV.")

    # 3. Image Content Verification (The core logic check)
    if images_exist:
        try:
            # Download images to temp for analysis
            img_paths = {}
            for img_name in expected_images:
                remote_path = f"/home/ga/ImageJ_Data/results/{img_name}"
                local_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.tif')
                local_tmp.close()
                copy_from_env(remote_path, local_tmp.name)
                img_paths[img_name] = local_tmp.name

            # Open images
            start_img = np.array(Image.open(img_paths["spindle_start.tif"]).convert('L'))
            end_img = np.array(Image.open(img_paths["spindle_end.tif"]).convert('L'))
            change_img = np.array(Image.open(img_paths["change_map.tif"]).convert('L'))

            # Verify dimensions
            if start_img.shape != end_img.shape or start_img.shape != change_img.shape:
                feedback.append("Image dimensions do not match.")
            else:
                # Calculate expected difference
                # ImageJ 'Difference' is |I1 - I2|
                # Allow for some minor pixel differences due to potential casting/saving
                # but correlation should be high.
                
                calculated_diff = np.abs(start_img.astype(int) - end_img.astype(int)).astype(np.uint8)
                
                # Compare calculated_diff with user's change_img
                # We can check Mean Squared Error or correlation
                mse = np.mean((calculated_diff - change_img) ** 2)
                
                # ImageJ might save 'change_map' as a 32-bit float or have different scaling
                # if the user didn't cast to 8-bit. 
                # Let's be lenient: check if the change map has high values where diff is high
                
                correlation = np.corrcoef(calculated_diff.flatten(), change_img.flatten())[0, 1]
                
                if correlation > 0.85:
                    score += 40
                    feedback.append("Change map content verified (matches mathematical difference).")
                elif mse < 100: # Low error
                    score += 40
                    feedback.append("Change map content verified (low MSE).")
                else:
                    feedback.append(f"Change map content mismatch (Corr: {correlation:.2f}). Did you use the 'Difference' operator?")
                    # Partial credit if it looks somewhat related
                    if correlation > 0.5:
                        score += 20

            # Cleanup images
            for p in img_paths.values():
                if os.path.exists(p):
                    os.unlink(p)

        except Exception as e:
            feedback.append(f"Error analyzing image content: {e}")

    # 4. Quantification Verification
    if csv_info.get("exists"):
        csv_data = result_data.get("csv_data", [])
        raw_content = result_data.get("csv_content_raw", "").lower()
        
        has_area = "area" in raw_content
        has_value = False
        
        # Check for numeric values in CSV
        import re
        numbers = re.findall(r'\b\d+\.?\d*\b', raw_content)
        if numbers:
            # Filter out indices (small integers) vs measurements (likely larger or float)
            measurements = [float(n) for n in numbers if float(n) > 0]
            if measurements:
                has_value = True

        if has_area and has_value:
            score += 10
            feedback.append("CSV contains Area measurements.")
        elif has_value:
            score += 5
            feedback.append("CSV contains numbers but missing 'Area' header.")
        else:
            feedback.append("CSV seems empty or invalid.")

    # Final check
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }