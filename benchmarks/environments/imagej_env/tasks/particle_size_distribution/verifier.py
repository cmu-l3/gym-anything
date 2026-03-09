#!/usr/bin/env python3
"""
Verifier for particle_size_distribution task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_particle_size_distribution(traj, env_info, task_info):
    """
    Verify particle size distribution analysis.
    
    Scoring (100 pts total):
    1. File creation & existence (10 pts)
    2. Data content (Individual rows) (20 pts)
    3. Columns present (Area, Perimeter, Diameter) (20 pts)
    4. Statistical Summary (Mean, CV, Std, etc.) (30 pts)
    5. Size Bins (10 pts)
    6. Plausibility (Mean diameter range) (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        copy_from_env("/tmp/particle_size_distribution_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    # 1. File existence (10 pts)
    if result.get("file_exists") and result.get("file_created_after_start"):
        score += 10
        feedback.append("Result file created successfully.")
    else:
        feedback.append("Result file missing or not created during task.")

    # 2. Individual Data Rows (20 pts)
    row_count = result.get("individual_row_count", 0)
    if row_count >= 20:
        score += 20
        feedback.append(f"Found {row_count} individual particle rows.")
    elif row_count > 5:
        score += 10
        feedback.append(f"Found {row_count} rows (expected > 20).")
    else:
        feedback.append("Insufficient individual particle data found.")

    # 3. Columns (20 pts)
    cols = []
    if result.get("has_area"): cols.append("Area")
    if result.get("has_perimeter"): cols.append("Perimeter")
    if result.get("has_diameter"): cols.append("Diameter")
    
    score += len(cols) * 6  # ~18 pts, round to 20 cap
    if len(cols) == 3: score = min(score + 2, 20) # Bonus to hit 20
    feedback.append(f"Columns found: {', '.join(cols)}.")

    # 4. Summary Stats (30 pts)
    reported = result.get("reported_stats", {})
    stats_found = 0
    if "mean" in reported: stats_found += 1
    if "cv" in reported: stats_found += 1
    if "std" in reported: stats_found += 1
    if "min" in reported: stats_found += 1
    if "max" in reported: stats_found += 1
    if "median" in reported: stats_found += 1
    
    score += stats_found * 5
    feedback.append(f"Summary statistics found: {stats_found}/6.")
    
    # Check consistency (CV approx Std/Mean)
    if "cv" in reported and "mean" in reported and "std" in reported:
        try:
            calc_cv = (reported["std"] / reported["mean"]) * 100
            if abs(calc_cv - reported["cv"]) < 5.0: # 5% tolerance
                feedback.append("CV calculation consistent.")
            else:
                feedback.append(f"CV inconsistency: Reported {reported['cv']}, Calc {calc_cv:.1f}")
        except: pass

    # 5. Size Bins (10 pts)
    if result.get("has_bins"):
        score += 10
        feedback.append("Size bin classification found.")

    # 6. Plausibility (10 pts)
    if result.get("mean_diameter_plausible"):
        score += 10
        feedback.append("Mean diameter value is plausible for Blobs image.")
    elif "mean" in reported and (15 < reported["mean"] < 45):
        score += 10
        feedback.append("Reported mean diameter is plausible.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }