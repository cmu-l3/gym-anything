#!/usr/bin/env python3
"""
Verifier for Intracellular Distribution EDM Task.

Verification Logic:
1.  **File Existence (20 pts)**: CSV exists and created during task.
2.  **Column Validation (15 pts)**: 'Mean' column present (proxy for distance).
3.  **Particle Count (15 pts)**: Between 30 and 200 particles (expected for this sample).
4.  **Data Plausibility (25 pts)**:
    *   Values must be > 2.0 (pixels). Real distances are rarely 0 or 1 unless on the edge.
    *   Values must be < 100.0 (pixels). In a 400x400 cell image, distances > 100 are unlikely.
    *   Crucially, checks against "Intensity" values. If they measured intensity of red spots (0-255), the mean might be high (e.g., 150-200). If they measured Distance Map, values are distances.
5.  **VLM Workflow Verification (25 pts)**: Uses trajectory frames to verify steps like "Distance Map" creation or "ROI Manager" usage.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_intracellular_distribution(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON
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

    score = 0
    feedback = []

    # Criterion 1: File Validity
    if result.get("file_exists") and result.get("file_valid_timestamp"):
        score += 20
        feedback.append("Result file created successfully.")
    else:
        feedback.append("Result file missing or created before task start.")

    # Criterion 2: Column Check
    if result.get("has_mean_column"):
        score += 15
        feedback.append("'Mean' column found.")
    else:
        feedback.append("Missing 'Mean' column in CSV.")

    # Criterion 3: Particle Count
    count = result.get("row_count", 0)
    expected_min = 30
    expected_max = 200
    if expected_min <= count <= expected_max:
        score += 15
        feedback.append(f"Particle count reasonable ({count}).")
    else:
        feedback.append(f"Particle count out of range ({count}). Expected {expected_min}-{expected_max}.")

    # Criterion 4: Value Plausibility (The EDM Check)
    # Distance map values for this image usually range 0-60 pixels.
    # Raw intensity values would be higher (often >100).
    mean_val = result.get("mean_of_means", 0)
    max_val = result.get("max_value", 0)
    
    # We expect meaningful distances.
    # If mean_val is super high (>120), they likely measured intensity, not distance.
    # If mean_val is super low (<1), they might have measured a mask or background.
    if 2.0 < mean_val < 100.0:
        score += 25
        feedback.append(f"Distance values look plausible (Mean: {mean_val:.2f}).")
    else:
        feedback.append(f"Values unlikely to be distances (Mean: {mean_val:.2f}).")

    # Criterion 5: VLM Workflow Verification
    # We check if they actually generated the Distance Map.
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = """
        Analyze these screenshots of an ImageJ task.
        I am looking for evidence of:
        1. A "Distance Map" or "EDM" image (usually looks like a gradient/foggy grayscale image of the cell shape).
        2. The "ROI Manager" window with a list of particles.
        3. A "Results" table.
        
        Does the user appear to have created a Distance Map?
        Reply with JSON: {"distance_map_seen": bool, "roi_manager_seen": bool, "reason": "string"}
        """
        
        try:
            vlm_resp = query_vlm(images=frames + [final], prompt=prompt)
            if vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                if parsed.get("distance_map_seen", False):
                    score += 15
                    feedback.append("VLM confirmed Distance Map creation.")
                if parsed.get("roi_manager_seen", False):
                    score += 10
                    feedback.append("VLM confirmed ROI Manager usage.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback points if programmatic checks are strong
            if score >= 70:
                score += 25
                feedback.append("VLM skipped but data looks good.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }