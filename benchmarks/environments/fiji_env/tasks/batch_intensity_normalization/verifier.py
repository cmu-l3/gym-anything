#!/usr/bin/env python3
"""
Verifier for Batch Intensity Normalization Task

Verifies:
1. 5 normalized images exist and are valid TIFFs.
2. Image statistics match target (Mean ~100, Std ~40).
3. CSV report exists and is valid.
4. Histogram comparison image exists.
5. Anti-gaming: Files created after task start.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_batch_normalization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verifier failed: copy_from_env not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Target values from metadata
    meta = task_info.get("metadata", {})
    TARGET_MEAN = meta.get("target_mean", 100)
    TARGET_STD = meta.get("target_std", 40)
    TOL_MEAN = meta.get("tolerance_mean", 20)
    TOL_STD = meta.get("tolerance_std", 15)

    # 1. Image Existence and Validity (10 pts per image = 50 pts total)
    images = result.get("images", {})
    valid_images = 0
    stats_passed = 0
    
    for fname, data in images.items():
        if not data.get("exists"):
            feedback.append(f"Missing file: {fname}")
            continue
            
        # Basic file validity check (created during task, has pixels)
        if not data.get("valid_timestamp"):
            feedback.append(f"{fname} was not created during the task window.")
            continue
            
        if data.get("unique_pixels", 0) < 10:
            feedback.append(f"{fname} seems empty or constant.")
            continue
            
        valid_images += 1
        
        # 2. Statistical Verification
        mean = data.get("mean", 0)
        std = data.get("std", 0)
        
        mean_ok = abs(mean - TARGET_MEAN) <= TOL_MEAN
        std_ok = abs(std - TARGET_STD) <= TOL_STD
        
        if mean_ok and std_ok:
            stats_passed += 1
        else:
            feedback.append(f"{fname} stats mismatch: Mean={mean:.1f} (Target {TARGET_MEAN}), Std={std:.1f} (Target {TARGET_STD})")

    # Score calculation for images
    # 5 images * 5 pts for existence/validity = 25 pts
    # 5 images * 5 pts for correct stats = 25 pts
    score += (valid_images * 5)
    score += (stats_passed * 5)
    
    if valid_images == 5:
        feedback.append("All 5 output images found.")
    
    # 3. CSV Report (25 pts)
    if result.get("report_exists"):
        if result.get("report_valid"):
            score += 25
            feedback.append("Normalization report is valid.")
        else:
            score += 10
            feedback.append("Report exists but missing columns or rows.")
    else:
        feedback.append("Normalization report CSV missing.")

    # 4. Histogram Image (25 pts)
    if result.get("histogram_exists"):
        score += 25
        feedback.append("Histogram comparison image found.")
    else:
        feedback.append("Histogram comparison image missing.")

    # Final Verdict
    # Threshold: Need valid images with correct stats (at least 3/5) AND report OR histogram
    # Min passing score roughly 60
    passed = score >= 60 and stats_passed >= 3
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }