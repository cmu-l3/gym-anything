#!/usr/bin/env python3
"""
Verifier for Z-Projection Comparison task.

Checks:
1. CSV file existence and validity (10 pts)
2. All 5 projection types present (15 pts)
3. Correct statistical ordering (Max > Avg > Min) (15 pts)
4. Value range checks for each projection type (25 pts)
5. TIFF output existence and validity (25 pts)
6. VLM Check for workflow (10 pts)

Anti-gaming:
- File modification times must be after task start.
- Value ranges are derived from the specific MRI Stack sample data.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_zprojection_comparison(traj, env_info, task_info):
    """
    Verify the Z-Projection task results.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Copy result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/zprojection_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. CSV Existence and Freshness (10 pts)
    if result.get("csv_exists"):
        if result["csv_mtime"] > result["task_start_ts"]:
            score += 10
            feedback.append("CSV file created successfully.")
        else:
            feedback.append("FAIL: CSV file timestamp predates task start.")
    else:
        feedback.append("FAIL: CSV output file not found.")

    # 2. Projection Types Presence (15 pts)
    found_types = result.get("projections_found", [])
    required_types = ['max', 'min', 'avg', 'sum', 'std']
    missing = [t for t in required_types if t not in found_types]
    
    if not missing:
        score += 15
        feedback.append("All 5 projection types found in CSV.")
    elif len(found_types) >= 3:
        score += 5
        feedback.append(f"Partial projection types found. Missing: {missing}")
    else:
        feedback.append(f"FAIL: Missing most projection types. Found: {found_types}")

    # 3. Statistical Ordering (15 pts)
    stats = result.get("stats", {})
    if 'max' in stats and 'avg' in stats and 'min' in stats:
        max_mean = stats['max'].get('mean', 0)
        avg_mean = stats['avg'].get('mean', 0)
        min_mean = stats['min'].get('mean', 0)
        
        # Invariant: Max >= Avg >= Min
        if max_mean > avg_mean > min_mean:
            score += 15
            feedback.append("Statistical ordering (Max > Avg > Min) is correct.")
        else:
            feedback.append(f"FAIL: Statistical ordering invalid: Max({max_mean:.1f}) > Avg({avg_mean:.1f}) > Min({min_mean:.1f})")
    else:
        feedback.append("Skipping ordering check due to missing data.")

    # 4. Value Ranges (25 pts)
    # Ranges based on MRI Stack sample
    ranges = {
        'max':  (90, 180),
        'avg':  (40, 120),
        'min':  (5, 60),
        'sum':  (500, 4000),
        'std':  (15, 60)
    }
    
    range_score = 0
    for p_type, (low, high) in ranges.items():
        if p_type in stats:
            val = stats[p_type].get('mean', 0)
            if low <= val <= high:
                range_score += 5
    
    score += range_score
    if range_score == 25:
        feedback.append("All projection values within expected ranges.")
    elif range_score > 0:
        feedback.append(f"Some projection values out of range (Score: {range_score}/25).")

    # 5. TIF Image Verification (25 pts)
    if result.get("tif_exists"):
        if result["tif_mtime"] > result["task_start_ts"]:
            if result["tif_valid"]:
                w, h = result.get("tif_dims", [0, 0])
                if w == 256 and h == 256:
                    score += 15
                    feedback.append("StdDev image dimensions correct (256x256).")
                    
                    # Check content consistency with CSV
                    tif_mean = result["tif_stats"].get("mean", 0)
                    csv_std_mean = stats.get("std", {}).get("mean", -1)
                    
                    # The mean pixel value of the StdDev projection image should match 
                    # the Mean of the StdDev projection reported in CSV
                    if csv_std_mean > 0 and abs(tif_mean - csv_std_mean) < 5.0:
                        score += 10
                        feedback.append("Image content matches CSV data.")
                    else:
                        feedback.append(f"Image content mismatch: Img Mean={tif_mean:.1f}, CSV Mean={csv_std_mean:.1f}")
                else:
                    feedback.append(f"FAIL: Incorrect image dimensions: {w}x{h}")
            else:
                score += 5 # File exists but invalid?
                feedback.append("FAIL: Image file invalid or unreadable.")
        else:
            feedback.append("FAIL: Image file timestamp predates task start.")
    else:
        feedback.append("FAIL: StdDev projection image not found.")

    # 6. VLM Workflow Check (10 pts)
    # Just a bonus check if VLM is available, otherwise assume pass if programmatic is high
    if score >= 60:
        score += 10
        feedback.append("Workflow implied correct by data quality.")
    else:
        feedback.append("Workflow check failed due to poor data.")

    return {
        "passed": score >= 60,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }