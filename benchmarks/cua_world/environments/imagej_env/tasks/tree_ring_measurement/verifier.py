#!/usr/bin/env python3
"""
Verifier for tree_ring_measurement task.

Verification Strategy:
1. Programmatic: Check if CSV exists, created during task, contains >= 5 measurements.
2. Data Validity: Check if measured widths are plausible (2-200px) and have variation (std_dev > 0).
3. VLM: Check trajectory for "Tree Rings" image and profile plot usage.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tree_ring_measurement(traj, env_info, task_info):
    """
    Verify tree ring measurement task.
    
    Scoring (100 pts):
    - File created during task: 15 pts
    - At least 5 measurements found: 25 pts
    - Values are plausible (2-250px) & vary: 25 pts
    - Summary stats present: 10 pts
    - VLM Verification (Process): 25 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Programmatic Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/tree_ring_measurement_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: File Existence & Timestamp (15 pts) ---
    if result.get("file_exists") and result.get("created_during_task"):
        score += 15
        feedback_parts.append("Result file created during task")
    elif result.get("file_exists"):
        score += 5
        feedback_parts.append("Result file exists but timestamp check failed")
    else:
        feedback_parts.append("Result file not found")

    # --- Criterion 2: Measurement Count (25 pts) ---
    count = result.get("valid_widths_count", 0)
    if count >= 5:
        score += 25
        feedback_parts.append(f"Found {count} ring measurements")
    elif count >= 1:
        score += 10
        feedback_parts.append(f"Found only {count} measurements (min 5 required)")
    else:
        feedback_parts.append("No valid measurements found")

    # --- Criterion 3: Data Validity (25 pts) ---
    # Plausible width for this image is roughly 10-60 pixels, but we allow 2-250
    # Must have variation (std dev > 0) to ensure they aren't just repeated numbers
    std_dev = result.get("width_std_dev", 0)
    mean_width = result.get("mean_width", 0)
    
    if count >= 1:
        if 2.0 <= mean_width <= 250.0:
            if std_dev > 0.1 or count == 1: # Single meas doesn't have std dev
                score += 25
                feedback_parts.append(f"Data values plausible (Mean: {mean_width:.1f}, SD: {std_dev:.1f})")
            else:
                score += 10
                feedback_parts.append("Data values plausible but lack variation (identical values?)")
        else:
            feedback_parts.append(f"Data values suspect (Mean: {mean_width:.1f}px) - out of expected range")

    # --- Criterion 4: Summary Stats (10 pts) ---
    if result.get("has_summary_stats"):
        score += 10
        feedback_parts.append("Summary statistics keywords found")
    else:
        feedback_parts.append("No summary statistics found")

    # --- Criterion 5: VLM Process Verification (25 pts) ---
    # We check if the agent actually opened the image and used the profile tool
    frames = sample_trajectory_frames(traj, n=6)
    
    vlm_prompt = """
    You are verifying an ImageJ task. Look at these sequential screenshots.
    The user should:
    1. Open an image that looks like tree rings (concentric light/dark circles).
    2. Draw a line across the rings.
    3. Open a 'Plot Profile' window (a 2D line graph of peaks and valleys).
    
    Answer in JSON:
    {
        "tree_rings_visible": boolean,
        "line_drawn": boolean,
        "profile_plot_visible": boolean,
        "reasoning": "string"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("tree_rings_visible"):
            vlm_score += 10
        if parsed.get("line_drawn") or parsed.get("profile_plot_visible"):
            vlm_score += 15
        
        feedback_parts.append(f"VLM: {parsed.get('reasoning', 'Analyzed')}")
    else:
        # Fallback if VLM fails: be lenient if data looks good
        if score >= 60:
            vlm_score += 15
            feedback_parts.append("VLM unavailable, skipped")

    score += vlm_score

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }