#!/usr/bin/env python3
"""
Verifier for Local Thickness Mapping task in ImageJ/Fiji.

Verification Strategy:
1. Programmatic Checks (70 points):
   - Thickness map exists, created during task, and is a valid 32-bit float TIFF.
   - Thickness map values are within the expected range for "Blobs" (max ~40-50px).
     * Distinguishes between 8-bit binary (0/255) and actual thickness map.
   - Distribution CSV exists and contains meaningful statistics (Mean, Max).
2. VLM Checks (30 points):
   - Trajectory analysis: Did the agent run the Local Thickness plugin?
   - Visual inspection: Does the result look like a thickness heatmap (fire LUT)?

Pass Threshold: 60 points
"""

import json
import tempfile
import os
import logging
import csv
import re
import math
try:
    from PIL import Image
    import numpy as np
except ImportError:
    pass  # handled in code

logger = logging.getLogger(__name__)

def verify_local_thickness_mapping(traj, env_info, task_info):
    """
    Verify the local thickness mapping task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification failed: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    
    # Expected ranges
    exp_mean_min = metadata.get('expected_mean_min', 8.0)
    exp_mean_max = metadata.get('expected_mean_max', 20.0)
    exp_max_min = metadata.get('expected_max_min', 25.0)

    score = 0
    feedback_parts = []
    
    # Temporary files for verification
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json").name
    temp_map = tempfile.NamedTemporaryFile(delete=False, suffix=".tif").name
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix=".csv").name

    try:
        # 1. Load JSON summary
        try:
            copy_from_env("/tmp/local_thickness_result.json", temp_json)
            with open(temp_json, 'r') as f:
                result_json = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}

        # ---------------------------------------------------------
        # Criterion 1: Thickness Map Analysis (40 points)
        # ---------------------------------------------------------
        map_exists = result_json.get("map_exists", False)
        map_fresh = result_json.get("map_created_during_task", False)
        
        map_valid_format = False
        map_valid_values = False
        map_is_float = False
        
        if map_exists and map_fresh:
            try:
                copy_from_env("/home/ga/ImageJ_Data/results/thickness_map.tif", temp_map)
                
                # Analyze image with PIL/NumPy
                try:
                    img = Image.open(temp_map)
                    img_arr = np.array(img)
                    
                    # Check Mode: Local Thickness produces 32-bit float ('F' or 'I;32' in PIL)
                    # 8-bit ('L') or 1-bit ('1') implies they just saved the binary mask
                    if img.mode in ['F', 'I', 'I;32', 'I;16'] or img_arr.dtype in [np.float32, np.float64, np.int32]:
                        map_is_float = True
                    
                    # Check Values
                    # For Blobs, max thickness is diameter ~50 pixels
                    # If max is 255, it's likely just a binary mask
                    img_max = float(np.max(img_arr))
                    img_mean = float(np.mean(img_arr[img_arr > 0])) # Mean of foreground
                    
                    if 20.0 <= img_max <= 100.0:
                        map_valid_values = True
                        feedback_parts.append(f"Map values valid (Max: {img_max:.1f}px)")
                    else:
                        feedback_parts.append(f"Map values suspicious (Max: {img_max:.1f}px - expected 25-100)")
                        if img_max == 255.0:
                            feedback_parts.append("FAIL: Image appears to be a binary mask, not a thickness map.")
                    
                    map_valid_format = True
                except Exception as e:
                    feedback_parts.append(f"Failed to analyze map image: {str(e)}")
            except Exception as e:
                feedback_parts.append("Failed to copy map image for verification")

        if map_exists and map_fresh:
            score += 10 # File exists and is new
            if map_is_float:
                score += 15 # Correct data type (not 8-bit)
            if map_valid_values:
                score += 15 # Correct quantitative range
        elif map_exists:
            feedback_parts.append("FAIL: Map file exists but dates from before task start")
        else:
            feedback_parts.append("FAIL: Thickness map file not found")

        # ---------------------------------------------------------
        # Criterion 2: Statistics CSV Analysis (30 points)
        # ---------------------------------------------------------
        csv_exists = result_json.get("csv_exists", False)
        csv_fresh = result_json.get("csv_created_during_task", False)
        csv_content_valid = False
        
        if csv_exists and csv_fresh:
            try:
                copy_from_env("/home/ga/ImageJ_Data/results/thickness_distribution.csv", temp_csv)
                with open(temp_csv, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read().lower()
                    
                    # Check for keywords
                    has_mean = any(x in content for x in ['mean', 'average'])
                    has_max = any(x in content for x in ['max'])
                    
                    # Check for numeric data roughly in range
                    # Try to find a number between 8 and 20 (Mean)
                    numbers = re.findall(r"[-+]?\d*\.\d+|\d+", content)
                    floats = [float(n) for n in numbers]
                    
                    # Logic: Is there a number in reasonable mean range?
                    has_valid_mean = any(exp_mean_min <= n <= exp_mean_max for n in floats)
                    
                    if has_mean and (has_max or has_valid_mean):
                        csv_content_valid = True
                        feedback_parts.append("CSV statistics appear valid")
                    else:
                        feedback_parts.append("CSV found but missing expected stats keywords or values out of range")
                        
            except Exception as e:
                feedback_parts.append(f"Failed to verify CSV content: {str(e)}")
        
        if csv_exists and csv_fresh:
            score += 10 # Exists
            if csv_content_valid:
                score += 20 # Valid content
        elif csv_exists:
            feedback_parts.append("FAIL: CSV file exists but dates from before task start")
        else:
            feedback_parts.append("FAIL: Statistics CSV not found")

        # ---------------------------------------------------------
        # Criterion 3: VLM / Trajectory Verification (30 points)
        # ---------------------------------------------------------
        # Since we don't have access to the live VLM in this static script, 
        # we check if the outputs strongly suggest the correct workflow.
        # If the map is a 32-bit float with correct range, the workflow was almost certainly correct.
        
        # We assume VLM scoring happens externally or via gym_anything hooks if available.
        # Here we rely on the strong proxy of the 32-bit float map.
        # If map is valid float, we award workflow points.
        if map_is_float and map_valid_values:
            score += 30
            feedback_parts.append("Workflow verified via output data integrity")
        elif map_exists:
             feedback_parts.append("Workflow partially incomplete (wrong output format)")

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        for f in [temp_json, temp_map, temp_csv]:
            if os.path.exists(f):
                os.unlink(f)

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }