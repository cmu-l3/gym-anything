#!/usr/bin/env python3
"""
Verifier for Boolean Overlap Analysis task.

Logic:
1. Retrieve the 3 mask images (Red, Green, Overlap) and the CSV count file.
2. Verify all files exist and were created after task start.
3. LOAD IMAGES:
   - Check they are binary (0/255).
   - Compute mathematical intersection: Expected = (Red > 0) & (Green > 0).
   - Compare 'Expected' vs 'Overlap' mask (Jaccard Index or pixel match %).
4. CHECK COUNTS:
   - Count connected components in the 'Overlap' mask.
   - Compare with row count in CSV.
"""

import json
import os
import tempfile
import logging
import csv
import numpy as np
from PIL import Image
from scipy import ndimage

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_boolean_overlap(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function unavailable"}

    # Define paths expected in the environment
    results_dir = "/home/ga/ImageJ_Data/results"
    paths = {
        "summary": "/tmp/boolean_overlap_result.json",
        "red": f"{results_dir}/mask_red.tif",
        "green": f"{results_dir}/mask_green.tif",
        "overlap": f"{results_dir}/mask_overlap.tif",
        "counts": f"{results_dir}/overlap_counts.csv"
    }

    # Temporary directory for analysis
    with tempfile.TemporaryDirectory() as temp_dir:
        # Helper to copy file
        def get_file(key):
            local_path = os.path.join(temp_dir, key)
            try:
                # Add extension for images to help PIL
                if "tif" in paths[key]:
                    local_path += ".tif"
                elif "csv" in paths[key]:
                    local_path += ".csv"
                
                copy_from_env(paths[key], local_path)
                if os.path.exists(local_path) and os.path.getsize(local_path) > 0:
                    return local_path
            except Exception as e:
                logger.warning(f"Could not copy {key}: {e}")
            return None

        # 1. Get Summary JSON first
        summary_path = get_file("summary")
        if not summary_path:
            return {"passed": False, "score": 0, "feedback": "Verification failed: Could not export task results."}
        
        with open(summary_path, 'r') as f:
            summary = json.load(f)

        # check timestamps
        task_start = summary.get("task_start_timestamp", 0)
        
        score = 0
        feedback = []
        
        # 2. Check File Existence & Timestamp (20 pts)
        files_exist = True
        for name in ["mask_red", "mask_green", "mask_overlap", "counts_csv"]:
            info = summary.get("files", {}).get(name, {})
            if not info.get("exists"):
                files_exist = False
                feedback.append(f"Missing file: {name}")
            elif info.get("mtime", 0) < task_start:
                files_exist = False
                feedback.append(f"Stale file detected: {name}")
        
        if files_exist:
            score += 20
        else:
            return {"passed": False, "score": score, "feedback": "Files missing or invalid: " + "; ".join(feedback)}

        # 3. Copy Images for Logic Check
        p_red = get_file("red")
        p_green = get_file("green")
        p_overlap = get_file("overlap")
        p_counts = get_file("counts")

        try:
            # Load images
            # Convert to numpy and normalize to 0-1 boolean
            img_red = np.array(Image.open(p_red)) > 0
            img_green = np.array(Image.open(p_green)) > 0
            img_overlap = np.array(Image.open(p_overlap)) > 0
            
            # 4. Check Binary Format (20 pts)
            # If we successfully loaded and they had valid shapes, give points
            # Ensure they are the same size
            if img_red.shape == img_green.shape == img_overlap.shape:
                score += 20
            else:
                return {
                    "passed": False, 
                    "score": score, 
                    "feedback": f"Image dimension mismatch: Red{img_red.shape} vs Green{img_green.shape}"
                }

            # 5. Verify Boolean Logic (40 pts)
            # Expected Overlap = Red AND Green
            expected_overlap = np.logical_and(img_red, img_green)
            
            # Compare pixels
            # Allow tiny tolerance (e.g. < 1% pixels mismatch) in case of different 
            # handling of edge pixels by different plugins, though ImageCalc should be exact.
            total_pixels = expected_overlap.size
            mismatch = np.sum(expected_overlap != img_overlap)
            match_percent = 100.0 * (1.0 - (mismatch / total_pixels))
            
            # Also check if masks are non-trivial (not all black or all white)
            if np.sum(img_red) == 0 or np.sum(img_green) == 0:
                feedback.append("One or more input masks are empty (all black).")
                # No points for logic if inputs are trivial
            elif match_percent > 99.0:
                score += 40
                feedback.append("Boolean logic (AND operation) verified correctly.")
            else:
                feedback.append(f"Boolean logic mismatch. Overlap image matches {match_percent:.2f}% of mathematical intersection.")

            # 6. Verify Quantification (20 pts)
            # Count connected components in the actual overlap image
            labeled_array, num_features = ndimage.label(img_overlap)
            
            # Read CSV rows
            csv_count = 0
            with open(p_counts, 'r') as f:
                # Handle ImageJ results table which often has a header
                reader = csv.reader(f)
                rows = list(reader)
                # Filter for non-empty data rows (simple heuristic: rows with numbers)
                for row in rows:
                    if row and any(c.replace('.','',1).isdigit() for c in row):
                        csv_count += 1
            
            # ImageJ Results table usually has 1 header row.
            # Analyze Particles often outputs 1 row per particle.
            # Sometimes there is a "Summary" window saved instead.
            # We assume "Display results" creates one row per particle.
            
            # Allow slight deviation (e.g. +/- 1 or 2) due to edge handling or 'count' vs 'rows'
            # If the CSV has a header, real data rows = len(rows) - 1
            # We used a heuristic above to count data rows.
            
            diff = abs(csv_count - num_features)
            
            if diff <= 2 and num_features > 0:
                score += 20
                feedback.append(f"Object count matches (Image: {num_features}, CSV: {csv_count}).")
            elif num_features == 0:
                feedback.append("Overlap image is empty, no objects to count.")
            else:
                feedback.append(f"Count mismatch. Image has {num_features} objects, CSV has {csv_count} rows.")

        except Exception as e:
            feedback.append(f"Error during image analysis: {str(e)}")
            import traceback
            traceback.print_exc()

        passed = score >= 80
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback)
        }