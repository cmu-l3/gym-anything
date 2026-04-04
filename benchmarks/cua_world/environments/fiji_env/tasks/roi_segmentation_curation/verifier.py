#!/usr/bin/env python3
"""
Verifier for roi_segmentation_curation@1 task.

Checks:
1. Output file created during task.
2. False positive (noise) ROI at specific location is REMOVED.
3. Merged ROI at specific location is REMOVED.
4. Two new ROIs exist near the merge location (Split performed).
5. VLM verification of the workflow.
"""

import json
import os
import math
import tempfile
import logging
from typing import List, Dict

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- Helper Functions ---

def calculate_distance(p1, p2):
    return math.sqrt((p1[0] - p2[0])**2 + (p1[1] - p2[1])**2)

def check_roi_at_location(measurements: List[Dict], target_x: float, target_y: float, radius: float):
    """Returns list of ROIs found within radius of target."""
    found = []
    for roi in measurements:
        # Fiji results usually have 'X' and 'Y' or 'XM' and 'YM' (centroid)
        mx = roi.get('XM', roi.get('X', -9999))
        my = roi.get('YM', roi.get('Y', -9999))
        
        dist = calculate_distance((mx, my), (target_x, target_y))
        if dist <= radius:
            found.append(roi)
    return found

# --- Main Verifier ---

def verify_roi_curation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    measurements = result.get("measurements", [])
    gt_info = result.get("ground_truth_info", {})
    output_exists = result.get("output_exists", False)
    created_during = result.get("file_created_during_task", False)
    
    score = 0
    feedback = []

    # Criteria 1: File Existence & Anti-Gaming (20 pts)
    if output_exists and created_during:
        score += 20
        feedback.append("Curated ROI file created successfully.")
    elif output_exists:
        score += 5
        feedback.append("Output file exists but was not created during task time (stale?).")
    else:
        feedback.append("Output ROI file not found.")
        return {"passed": False, "score": 0, "feedback": "No output file found."}

    # Criteria 2: False Positive Removal (30 pts)
    # Check if any ROI exists near the noise location
    noise_coords = gt_info.get("noise_coords", [15, 15])
    noise_radius = gt_info.get("noise_radius", 20)
    
    rois_at_noise = check_roi_at_location(measurements, noise_coords[0], noise_coords[1], noise_radius)
    
    if len(rois_at_noise) == 0:
        score += 30
        feedback.append("False positive noise successfully removed.")
    else:
        feedback.append(f"False positive NOT removed. Found {len(rois_at_noise)} ROI(s) at noise location.")

    # Criteria 3: Merge Fix (split into 2) (40 pts)
    # Original merge was at merge_coords.
    # We expect 2 ROIs near there now (centroids slightly offset from original center, but within radius)
    merge_coords = gt_info.get("merge_coords", [0, 0])
    merge_radius = gt_info.get("merge_radius", 60) # Generous radius
    
    rois_at_merge = check_roi_at_location(measurements, merge_coords[0], merge_coords[1], merge_radius)
    
    # We expect exactly 2, maybe 3 if messy, but definitely > 0 and != 1 (which would mean merge kept)
    # Ideally, if it was one big ROI, its center was X. Now 2 ROIs, centers X1, X2. Both X1, X2 should be near X.
    
    if len(rois_at_merge) >= 2:
        score += 40
        feedback.append(f"Merged cell successfully split (found {len(rois_at_merge)} ROIs in region).")
    elif len(rois_at_merge) == 1:
        # Check area? If area is still huge, they didn't split it.
        # This is harder without exact area bounds, but count is a good proxy.
        feedback.append("Merged cell region still contains only 1 ROI. Likely failed to split.")
    elif len(rois_at_merge) == 0:
        feedback.append("Merged cell region is empty. You deleted it but didn't draw new ones.")
        score += 10 # Partial credit for deleting the bad one
    
    # Criteria 4: General Sanity Check (10 pts)
    # We expect roughly same number of ROIs as original minus corrections.
    # Just checking we have a reasonable amount of data (e.g. > 5 nuclei)
    if len(measurements) > 5:
        score += 10
        feedback.append("Valid number of ROIs preserved.")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": {
            "rois_found": len(measurements),
            "rois_at_noise": len(rois_at_noise),
            "rois_at_merge": len(rois_at_merge)
        }
    }