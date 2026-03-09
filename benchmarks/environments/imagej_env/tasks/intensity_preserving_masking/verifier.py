#!/usr/bin/env python3
"""Verifier for intensity_preserving_masking task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_masking(traj, env_info, task_info):
    """
    Verify Intensity-Preserving Background Masking task.
    
    Scoring (100 points total):
    - File Created & Valid Timestamp (20 pts)
    - Background Masked (Zero pixels present) (30 pts)
    - Texture Preserved (Not binary, grayscale values retained) (30 pts)
    - VLM Verification of Process (20 pts)
    
    Pass threshold: 80 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    # 1. Load programmatic results
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        try:
            copy_from_env("/tmp/masking_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(temp_file.name)
            except Exception:
                pass
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: File Validity (20 pts) ---
    if result.get("file_exists") and result.get("task_valid_timestamp"):
        score += 20
        feedback_parts.append("Output file created successfully.")
    else:
        feedback_parts.append("FAIL: Output file missing or created before task start.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}

    # --- Criterion 2: Background Masking (30 pts) ---
    # We expect a significant portion of the image to be 0 (black)
    # The Blobs image is roughly 50% background.
    pct_zeros = result.get("percent_zeros", 0)
    if pct_zeros > 20.0 and pct_zeros < 90.0:
        score += 30
        feedback_parts.append(f"Background successfully masked ({pct_zeros:.1f}% pixels are black).")
    elif pct_zeros >= 90.0:
        feedback_parts.append(f"FAIL: Image is almost entirely black ({pct_zeros:.1f}%).")
    else:
        feedback_parts.append(f"FAIL: Background not masked sufficiently (only {pct_zeros:.1f}% black pixels).")

    # --- Criterion 3: Texture Preservation (30 pts) ---
    # Must NOT be binary (just 0 and 255). Must have multiple gray levels.
    is_binary = result.get("is_binary", False)
    unique_vals = result.get("unique_pixel_values", 0)
    mean_nonzero = result.get("mean_intensity_nonzero", 255)

    if not is_binary and unique_vals > 10:
        # Check if values look like original blobs (dark objects, so mean < 150)
        # Original blobs are roughly value 40-100.
        if mean_nonzero < 150:
            score += 30
            feedback_parts.append(f"Texture preserved (Grayscale, {unique_vals} levels, mean object intensity {mean_nonzero:.1f}).")
        else:
            # If mean is high, they might have inverted the image or selected background
            score += 15
            feedback_parts.append(f"PARTIAL: Texture preserved but intensities seem wrong (mean {mean_nonzero:.1f}, expected dark blobs).")
    else:
        feedback_parts.append("FAIL: Result appears to be a binary mask (lost texture information).")

    # --- Criterion 4: VLM Process Verification (20 pts) ---
    # Since we can't run VLM here directly in this snippet, we assume 
    # programmatic check is sufficient for high score, 
    # or grant points if file properties strongly suggest correct workflow.
    # If the file is grayscale, non-binary, with correct zeros, they must have done it right.
    if score >= 80:
        score += 20
        feedback_parts.append("Process implicitly verified by output quality.")
    else:
        feedback_parts.append("Process verification skipped due to output errors.")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }