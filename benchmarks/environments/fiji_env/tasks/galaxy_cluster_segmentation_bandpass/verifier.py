#!/usr/bin/env python3
"""
Verifier for Galaxy Cluster Segmentation Task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_galaxy_cluster_segmentation(traj, env_info, task_info):
    """
    Verifies the galaxy cluster segmentation task.
    
    Scoring Criteria:
    1. Filtered image created & timestamp valid (20 pts)
    2. CSV measurement file created (20 pts)
    3. Mask image created (10 pts)
    4. Cluster count within expected range (100-1000) (30 pts)
    5. Mean cluster area reasonable (indicating measurement filter applied) (10 pts)
    6. Filtered image statistics (10 pts) - checking against empty/black image
    
    Total: 100 pts
    Pass Threshold: 70 pts
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment interface error."}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # --- Check 1: Filtered Image (20 pts) ---
    if result.get('filtered_image_exists') and result.get('timestamp_valid'):
        score += 20
        feedback.append("Filtered image created during task.")
    elif result.get('filtered_image_exists'):
        score += 10
        feedback.append("Filtered image exists but timestamp uncertain.")
    else:
        feedback.append("Filtered image not found.")

    # --- Check 2: CSV Existence (20 pts) ---
    if result.get('csv_exists') and result.get('csv_valid'):
        score += 20
        feedback.append("Measurements CSV created and valid.")
    elif result.get('csv_exists'):
        score += 10
        feedback.append("Measurements CSV exists but missing required columns.")
    else:
        feedback.append("Measurements CSV not found.")

    # --- Check 3: Mask Existence (10 pts) ---
    if result.get('mask_exists'):
        score += 10
        feedback.append("Mask image created.")
    else:
        feedback.append("Mask image not found.")

    # --- Check 4: Cluster Count (30 pts) ---
    count = result.get('cluster_count', 0)
    # 100-1000 is the expected range for M51 with these filter settings
    if 80 <= count <= 1200:
        score += 30
        feedback.append(f"Cluster count ({count}) is within expected range.")
    elif count > 0:
        score += 10
        feedback.append(f"Cluster count ({count}) is outside optimal range (80-1200).")
    else:
        feedback.append("No clusters detected.")

    # --- Check 5: Particle Size Filtering (10 pts) ---
    # We asked for 5-500 pixels. The mean should reflect this.
    mean_area = result.get('mean_area', 0)
    if 5 <= mean_area <= 500:
        score += 10
        feedback.append(f"Mean particle area ({mean_area:.1f}) indicates size filtering applied.")
    elif count > 0:
        feedback.append(f"Mean particle area ({mean_area:.1f}) is suspicious.")

    # --- Check 6: Image Content (10 pts) ---
    # Ensure image isn't purely black or white
    stats = result.get('image_stats', {})
    std_dev = stats.get('std_dev', 0)
    if std_dev > 1.0: # Arbitrary low threshold to ensure it's not a flat field
        score += 10
        feedback.append("Filtered image content verified.")
    else:
        feedback.append("Filtered image appears empty or flat.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }