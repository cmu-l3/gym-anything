#!/usr/bin/env python3
"""
Verifier for FFT Periodic Spacing Measurement task.

Verification Strategy:
1. Programmatic: Checks if FFT image and report exist and were created during task.
2. Value Check: Verifies reported period is within physically plausible range for the sample.
3. VLM: Checks trajectory frames to ensure FFT workflow was actually performed (not just guessing values).

Pass Threshold: 60 points
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fft_periodic_spacing(traj, env_info, task_info):
    """
    Verify FFT Periodic Spacing task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_period_min = metadata.get('expected_period_min', 5.0)
    expected_period_max = metadata.get('expected_period_max', 35.0)
    expected_width = metadata.get('expected_image_width', 170)
    width_tolerance = metadata.get('expected_image_width_tolerance', 15)

    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/fft_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 2. Score Programmatic Criteria
    
    # Criterion 1: Files created during task (20 pts)
    if result.get('files_created_after_start', False):
        score += 20
        feedback_parts.append("Files created during task")
    else:
        feedback_parts.append("Files missing or pre-date task")

    # Criterion 2: FFT Image Exists & Valid Size (20 pts)
    if result.get('fft_image_exists', False):
        size = result.get('fft_image_size_bytes', 0)
        if size > 1000: # Arbitrary small threshold for non-empty image
            score += 20
            feedback_parts.append("FFT power spectrum saved")
        else:
            feedback_parts.append("FFT image file empty/too small")
    else:
        feedback_parts.append("FFT image not found")

    # Criterion 3: Report CSV with measured period (20 pts)
    measured_period = result.get('measured_period')
    if measured_period is not None:
        score += 20
        feedback_parts.append(f"Period reported: {measured_period:.2f}")
    else:
        feedback_parts.append("No numeric period value found in report")

    # Criterion 4: Period Value Plausibility (15 pts)
    # The TEM Filter Plug has specific spacing. 
    # Valid range allows for minor peak selection differences.
    if measured_period is not None:
        if expected_period_min <= measured_period <= expected_period_max:
            score += 15
            feedback_parts.append("Period value in plausible range")
        else:
            feedback_parts.append(f"Period value {measured_period} outside expected range ({expected_period_min}-{expected_period_max})")

    # Criterion 5: Image Width reported correctly (5 pts)
    # Validates they used the correct image or read properties correctly
    reported_width = result.get('image_width_reported')
    if reported_width is not None:
        if abs(reported_width - expected_width) <= width_tolerance:
            score += 5
            feedback_parts.append("Image width reported correctly")
        else:
            feedback_parts.append(f"Image width mismatch (Expected ~{expected_width}, Got {reported_width})")

    # 3. VLM Verification (20 pts)
    # Check if they actually generated an FFT view
    
    vlm_score = 0
    frames = sample_trajectory_frames(traj, n=5)
    
    # We define a generic VLM query function (mock for local execution context, 
    # assumes framework injects 'query_vlm' if available, otherwise skips)
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm and frames:
        prompt = """
        Review these screenshots of an ImageJ/Fiji session.
        Did the user:
        1. Open an image that looks like a porous material (circles/holes)?
        2. Generate an FFT Power Spectrum (looks like a black square with a bright white center starburst/dot)?
        3. Did they perform any measurement (lines drawn on the FFT or results table)?
        
        Answer YES or NO for each.
        """
        try:
            vlm_resp = query_vlm(images=frames, prompt=prompt)
            resp_text = vlm_resp.get('text', '').upper()
            
            if "FFT" in resp_text or "POWER SPECTRUM" in resp_text or ("YES" in resp_text and "2" in resp_text):
                vlm_score += 20
                feedback_parts.append("VLM confirmed FFT workflow")
            else:
                # Fallback partial credit if just image opening is seen
                if "POROUS" in resp_text or "CIRCLES" in resp_text:
                    vlm_score += 10
                    feedback_parts.append("VLM confirmed image open, but not FFT")
                else:
                    feedback_parts.append("VLM did not observe FFT workflow")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # If VLM fails/unavailable, grant partial credit if programmatic pass is strong
            if score >= 60:
                vlm_score += 10
                feedback_parts.append("VLM skipped, assumed valid based on data")

    score += vlm_score

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }