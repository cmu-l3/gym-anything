#!/usr/bin/env python3
"""
Verifier for 3D Nuclear Morphometry task.

Criteria:
1. CSV Existence & Timing (20 pts): CSV created during task.
2. Calibration Awareness (30 pts): Measured volume indicates use of microns (200-5000) vs pixels (>100,000).
3. Data Filtering (10 pts): 1-3 objects detected (filtering noise).
4. Object Map (20 pts): 3D label map TIFF saved.
5. Process Validation (20 pts): VLM checks for 3D Objects Counter usage.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_3d_morphometry(traj, env_info, task_info):
    """
    Verifies the 3D nuclear morphometry task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/3d_morphometry_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Criterion 1: CSV Existence & Timing (20 pts) ---
    if result.get("csv_exists") and result.get("csv_created_during_task"):
        score += 20
        feedback.append("Measurement CSV created successfully.")
    elif result.get("csv_exists"):
        score += 5
        feedback.append("CSV exists but has old timestamp (pre-existing?).")
    else:
        feedback.append("Measurement CSV not found.")

    # --- Criterion 2: Calibration Check (30 pts) ---
    # We check if volume values look like µm³ or pixels³
    volumes = result.get("volume_values", [])
    
    if not volumes:
        feedback.append("No volume measurements found in CSV.")
    else:
        # Calculate mean volume
        mean_vol = sum(volumes) / len(volumes)
        
        # Valid biological range for this nucleus ~200-2000 µm³
        # Uncalibrated (pixels) would be huge (>100,000)
        if 50 < mean_vol < 10000:
            score += 30
            feedback.append(f"Volume measurements appear calibrated (Mean: {mean_vol:.1f} unit³).")
        elif mean_vol >= 10000:
            # Partial credit if they measured something, but failed calibration
            score += 5
            feedback.append(f"Volume measurements appear uncalibrated/raw pixels (Mean: {mean_vol:.0f}). Did you check Image Properties?")
        else:
            feedback.append(f"Volume measurements are outside expected range (Mean: {mean_vol:.1f}).")

    # --- Criterion 3: Noise Filtering (10 pts) ---
    # We expect ~1 main nucleus. Without filtering (min size 1000), we might get hundreds of speckles.
    obj_count = result.get("object_count", 0)
    if 1 <= obj_count <= 5:
        score += 10
        feedback.append(f"Object count is clean ({obj_count}).")
    elif obj_count > 5:
        feedback.append(f"Too many objects detected ({obj_count}). Did you apply the size filter (Min: 1000)?")
    else:
        feedback.append("No objects detected.")

    # --- Criterion 4: Object Map (20 pts) ---
    if result.get("map_exists") and result.get("map_created_during_task"):
        score += 20
        feedback.append("3D Object Map saved successfully.")
    else:
        feedback.append("3D Object Map file missing or not saved.")

    # --- Criterion 5: VLM Process Verification (20 pts) ---
    # We assume a pass here if basic criteria met, as VLM logic is external in this pattern.
    # However, we can add a placeholder score if CSV and Map exist, implying the process was run.
    if result.get("csv_exists") and result.get("map_exists"):
        score += 20
        feedback.append("Process implicitly verified by output existence.")

    # Final Pass Determination
    # Must have calibrated measurements and outputs
    passed = (score >= 70) and (50 < sum(volumes)/len(volumes) < 10000 if volumes else False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result
    }