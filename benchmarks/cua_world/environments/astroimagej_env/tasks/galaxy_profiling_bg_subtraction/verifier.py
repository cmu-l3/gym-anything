#!/usr/bin/env python3
"""
Verifier for Galaxy Profiling and Background Subtraction task.

Evaluation Criteria:
1. Background measured & saved (CSV check, realistic mean)
2. Subtracted image saved & 32-bit float (FITS header BITPIX = -32)
3. Mathematical precision: (Original - Subtracted) mean matches BG mean exactly,
   and standard deviation is near 0 (proving negative values weren't clipped).
4. Profile CSV extracted with proper core intersection (max > min).
5. VLM trajectory verification (GUI interactions).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_galaxy_profiling(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Background CSV (15 points)
    bg_exists = result.get('bg_csv_exists', False)
    bg_recent = result.get('bg_csv_recent', False)
    bg_mean = result.get('bg_mean')
    
    if bg_exists and bg_recent and bg_mean is not None:
        if 0 < bg_mean < 10000:  # Plausible background level
            score += 15
            feedback_parts.append(f"Valid background measured (Mean: {bg_mean:.2f})")
        else:
            score += 5
            feedback_parts.append(f"Background measured but mean seems implausible ({bg_mean})")
    else:
        feedback_parts.append("Background CSV missing or not newly created")

    # 2. FITS Format & 32-bit Float Conversion (20 points)
    fits_exists = result.get('fits_exists', False)
    fits_recent = result.get('fits_recent', False)
    bitpix = result.get('bitpix')
    
    if fits_exists and fits_recent:
        score += 10
        feedback_parts.append("Subtracted FITS saved")
        if bitpix == -32:
            score += 10
            feedback_parts.append("Image properly converted to 32-bit float")
        else:
            feedback_parts.append(f"WARNING: Image is not 32-bit float (BITPIX={bitpix})")
    else:
        feedback_parts.append("Subtracted FITS missing or not newly created")

    # 3. Mathematical Precision / Subtraction Integrity (25 points)
    mean_diff = result.get('mean_diff')
    std_diff = result.get('std_diff')
    
    math_passed = False
    if mean_diff is not None and std_diff is not None and bg_mean is not None:
        # Check if the subtracted amount matches the measured mean
        if abs(mean_diff - bg_mean) < 1.0:
            score += 15
            feedback_parts.append("Constant subtraction amount matches measured mean")
            
            # Check for clipping (std_diff should be ~0.0 if perfectly uniform subtraction occurred)
            if std_diff < 0.1:
                score += 10
                math_passed = True
                feedback_parts.append("Subtraction is uniform (no zero-clipping detected)")
            else:
                feedback_parts.append("WARNING: Subtraction non-uniform. Data was likely clipped at 0 due to missing float conversion.")
        else:
            feedback_parts.append(f"Subtraction mismatch. Measured: {bg_mean}, Subtracted: {mean_diff}")
            
    # 4. Spatial Profile (15 points)
    prof_exists = result.get('profile_exists', False)
    prof_recent = result.get('profile_recent', False)
    prof_len = result.get('profile_len', 0)
    prof_max = result.get('profile_max')
    prof_min = result.get('profile_min')
    
    if prof_exists and prof_recent and prof_len >= 30:
        if prof_max is not None and prof_min is not None and prof_max > prof_min * 1.5:
            score += 15
            feedback_parts.append(f"Valid core profile extracted (Len: {prof_len}, Peak: {prof_max:.1f})")
        else:
            score += 5
            feedback_parts.append("Profile extracted but does not clearly hit the galaxy core")
    else:
        feedback_parts.append("Profile CSV missing, invalid, or too short")

    # 5. VLM Trajectory Verification (25 points)
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = (
            "Review these screenshots of an AstroImageJ workflow. "
            "Did the user perform actions such as drawing rectangular boxes, "
            "opening the Math > Subtract dialog, or generating a Plot Profile window? "
            "Reply with 'Yes' if there is visual evidence of UI workflow, or 'No' if not."
        )
        
        vlm_resp = query_vlm(images=frames + [final], prompt=prompt)
        if "yes" in vlm_resp.lower():
            score += 25
            feedback_parts.append("VLM visual verification passed")
        else:
            feedback_parts.append("VLM could not confirm UI usage")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        # Give benefit of doubt if VLM fails but math proves it
        if math_passed:
            score += 25
            feedback_parts.append("VLM failed but math proves workflow (points awarded)")

    # Final pass logic
    passed = score >= 70 and math_passed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }