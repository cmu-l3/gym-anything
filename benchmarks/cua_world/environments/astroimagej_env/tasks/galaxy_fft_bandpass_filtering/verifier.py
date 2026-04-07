#!/usr/bin/env python3
"""
Verifier for galaxy_fft_bandpass_filtering task in AstroImageJ.
Uses hybrid programmatic data analysis + VLM trajectory verification.
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_galaxy_fft_bandpass_filtering(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Copy result JSON from VM
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result file error: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    score = 0
    feedback = []

    fits_exists = result.get('fits_exists', False)
    fits_created = result.get('fits_created_during_task', False)
    same_dims = result.get('same_dimensions', False)
    is_modified = result.get('is_modified', False)
    contrast_reduced = result.get('contrast_reduced', False)
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')

    # Criterion 1: Output file exists and was created during task (10 pts)
    if fits_exists and fits_created:
        score += 10
        feedback.append("Filtered FITS file saved correctly.")
    elif fits_exists:
        score += 3
        feedback.append("Filtered FITS file found, but appears to be unmodified from before task start.")
    else:
        feedback.append("Filtered FITS file (uit_bandpass_filtered.fits) not found.")

    # Criterion 2: Correct Dimensions (10 pts)
    if same_dims:
        score += 10
        feedback.append("Output image dimensions match the original.")
    elif fits_exists:
        feedback.append("Output image dimensions do NOT match the original.")

    # Criterion 3: Image is actually modified (10 pts)
    if is_modified:
        score += 10
        feedback.append("Output image data is successfully modified from raw data.")
    elif fits_exists:
        feedback.append("Output image is identical to the raw image. Filter was not applied.")

    # Criterion 4: Background Flattening / Large Structure Suppression (25 pts)
    if contrast_reduced:
        score += 25
        feedback.append("Central core vs edge contrast is significantly reduced, indicating successful high-pass/bandpass filtering.")
    elif is_modified:
        feedback.append("Image is modified, but central core was not adequately suppressed (incorrect filter used?).")

    # Criterion 5: Report File Exists (10 pts)
    if report_exists:
        score += 10
        feedback.append("Report file found.")
    else:
        feedback.append("Report file (filter_report.txt) not found.")

    # Criterion 6: Report Accuracy (15 pts)
    if report_exists:
        content_lower = report_content.lower()
        has_40 = "40" in content_lower
        has_3 = "3" in content_lower
        
        if has_40 and has_3:
            score += 15
            feedback.append("Report contains correct filter parameters (40 and 3).")
        elif has_40 or has_3:
            score += 7
            feedback.append("Report contains only one of the correct filter parameters.")
        else:
            feedback.append("Report does not contain the expected filter parameters.")

    # Criterion 7: VLM Verification using Trajectory Frames (20 pts)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """You are verifying an AstroImageJ task.
The user was supposed to:
1. Open a FITS galaxy image.
2. Use the FFT Bandpass Filter dialog (Process > FFT > Bandpass Filter...).
3. Save the result and measure statistics.

Examine the provided screenshots from the session. Look closely for:
- The "Bandpass Filter" dialog box open on the screen
- The progress or result of an FFT operation
- ImageJ processing menus being accessed

Did the agent perform or attempt the FFT Bandpass filtering?

Respond in JSON format:
{
    "fft_filter_used": true/false,
    "reasoning": "Briefly describe what you see that proves or disproves the use of the Bandpass Filter"
}
"""
            vlm_res = query_vlm(prompt=prompt, images=images)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('fft_filter_used', False):
                    score += 20
                    feedback.append("VLM confirmed FFT Bandpass Filter workflow in trajectory.")
                else:
                    feedback.append(f"VLM did not observe FFT Bandpass Filter workflow. Reason: {parsed.get('reasoning', '')}")
            else:
                feedback.append("VLM query failed or returned no result.")
        except Exception as e:
            feedback.append(f"VLM exception: {e}")
            
    # Key criteria for passing: File must exist, be created/modified, and have successful filtering
    key_criteria_met = fits_exists and fits_created and is_modified and contrast_reduced
    passed = score >= 70 and key_criteria_met

    if not passed and score >= 70:
        feedback.append("FAILED: Met score threshold but missing key programmatic filtering criteria.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }