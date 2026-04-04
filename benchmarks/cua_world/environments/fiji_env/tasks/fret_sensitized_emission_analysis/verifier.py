#!/usr/bin/env python3
"""
Verifier for fret_sensitized_emission_analysis task.

Criteria:
1. Output file exists and created during task.
2. Donor bleed-through region is correctly subtracted (intensity near 0).
3. Acceptor cross-excitation region is correctly subtracted (intensity near 0).
4. True FRET signal is preserved (intensity > threshold).
5. VLM check on process (optional/supplementary).

Pass Threshold: 70/100 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fret_sensitized_emission_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy missing"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File Existence and Timing (20 pts)
    output_exists = result.get("output_exists", False)
    created_during = result.get("file_created_during_task", False)
    
    if output_exists:
        if created_during:
            score += 20
            feedback_parts.append("Output file created successfully.")
        else:
            score += 5
            feedback_parts.append("Output file exists but timestamp is old.")
    else:
        feedback_parts.append("Output file 'corrected_fret.tif' not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}

    # 2. Quantitative Verification (80 pts)
    metrics = result.get("metrics", {})
    if not metrics.get("valid_image", False):
        return {"passed": False, "score": score, "feedback": "Output file is not a valid image or could not be opened."}

    # Thresholds
    # Ideal corrected background is 0 (or near 0 with noise subtraction).
    # Raw background was 10. 
    # Donor Blob: Raw~60. Target~0.
    # Acceptor Blob: Raw~44. Target~0.
    # FRET Blob: Raw~170. Target~100.
    
    # We allow some range due to noise and int/float conversion variations
    BLEED_TOLERANCE = 15.0  # Should be close to 0
    SIGNAL_THRESHOLD = 50.0 # Should be around 100
    
    donor_mean = metrics.get("donor_bleed_mean", 999)
    acceptor_mean = metrics.get("acceptor_bleed_mean", 999)
    fret_mean = metrics.get("fret_signal_mean", 0)
    
    # Check Donor Correction (25 pts)
    # The agent might just subtract background, so checking that it's low is key.
    # If they didn't correct, it would be ~60.
    if abs(donor_mean) < BLEED_TOLERANCE:
        score += 25
        feedback_parts.append(f"Donor bleed-through correctly removed (Mean: {donor_mean:.1f}).")
    elif donor_mean < 40:
        score += 10
        feedback_parts.append(f"Donor bleed-through partially removed or noisy (Mean: {donor_mean:.1f}).")
    else:
        feedback_parts.append(f"Donor bleed-through NOT removed (Mean: {donor_mean:.1f}, Expected < {BLEED_TOLERANCE}).")

    # Check Acceptor Correction (25 pts)
    # If uncorrected, would be ~44.
    if abs(acceptor_mean) < BLEED_TOLERANCE:
        score += 25
        feedback_parts.append(f"Acceptor cross-excitation correctly removed (Mean: {acceptor_mean:.1f}).")
    elif acceptor_mean < 30:
        score += 10
        feedback_parts.append(f"Acceptor cross-excitation partially removed (Mean: {acceptor_mean:.1f}).")
    else:
        feedback_parts.append(f"Acceptor cross-excitation NOT removed (Mean: {acceptor_mean:.1f}).")

    # Check FRET Signal Preservation (20 pts)
    # Should be around 100.
    if fret_mean > SIGNAL_THRESHOLD:
        score += 20
        feedback_parts.append(f"FRET signal preserved (Mean: {fret_mean:.1f}).")
    else:
        feedback_parts.append(f"FRET signal lost or too low (Mean: {fret_mean:.1f}).")

    # Bonus: 32-bit Float check (10 pts)
    # Important for scientific accuracy in this task
    if metrics.get("is_float", False):
        score += 10
        feedback_parts.append("Correct 32-bit float format used.")
    else:
        feedback_parts.append("Output is not 32-bit float (precision loss risk).")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }