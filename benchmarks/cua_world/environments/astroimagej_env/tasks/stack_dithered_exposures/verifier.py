#!/usr/bin/env python3
"""
Verifier for Stack Dithered Exposures task.

Verification Strategy (Hybrid: Programmatic + VLM):
1. Output file exists and was created after task start (15 pts)
2. Valid FITS file, not an exact copy of a single frame (10 pts)
3. FWHM (Sharpness) check: Stacking without aligning causes huge FWHM. (25 pts)
4. Ellipticity check: Misalignment causes elongated/streaked stars. (20 pts)
5. Noise reduction check: Relative noise should decrease from stacking. (10 pts)
6. VLM Trajectory Check: Agent used the alignment tool/sequence in AIJ. (20 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_ALIGNMENT_PROMPT = """You are verifying an astronomical image processing task in AstroImageJ.

The user was asked to 'Align' and 'Stack' a sequence of dithered exposures.
Look through these chronological trajectory frames and determine if the agent used the alignment tools.

Indicators of alignment:
- The "Align stack using apertures" or similar dialog window is visible.
- Red/blue aperture circles are placed on stars to be used as alignment references.
- The user is seen clicking through the alignment interface.
- "Z Project" or "Stack" dialogs appearing AFTER alignment.

Respond in JSON format:
{
    "alignment_dialog_visible": true/false,
    "apertures_placed_for_alignment": true/false,
    "stacking_performed": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""

def verify_stack_dithered_exposures(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # Retrieve data from container
    # ------------------------------------------------------------------
    try:
        # Task start time
        start_temp = tempfile.NamedTemporaryFile(delete=False)
        copy_from_env("/tmp/task_start_time", start_temp.name)
        with open(start_temp.name, 'r') as f:
            task_start = float(f.read().strip())
        os.unlink(start_temp.name)
        
        # Results JSON
        res_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", res_temp.name)
        with open(res_temp.name, 'r') as f:
            result = json.load(f)
        os.unlink(res_temp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification data: {e}"}

    # ------------------------------------------------------------------
    # Programmatic Checks
    # ------------------------------------------------------------------
    output_exists = result.get('output_exists', False)
    valid_fits = result.get('valid_fits', False)
    is_copy = result.get('is_exact_copy', False)
    file_mtime = result.get('file_mtime', 0)
    
    ref_stats = result.get('ref_stats')
    out_stats = result.get('out_stats')

    # 1 & 2. Existence and Integrity (25 pts)
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output file master_stack.fits not found."}
        
    if file_mtime > task_start:
        score += 15
        feedback_parts.append("File created during task.")
    else:
        feedback_parts.append("File existed before task start (possible gaming).")
        
    if valid_fits and not is_copy:
        score += 10
        feedback_parts.append("Valid stacked FITS file.")
    elif is_copy:
        feedback_parts.append("Output is an exact copy of the input frame. No stacking performed.")
    else:
        feedback_parts.append("Output is not a valid FITS file.")
        
    # 3 & 4 & 5. Astronomical Image Quality Checks
    if out_stats and ref_stats and not is_copy:
        ref_fwhm = ref_stats.get('fwhm_median', 5.0)
        out_fwhm = out_stats.get('fwhm_median', 5.0)
        ref_ellip = ref_stats.get('ellipticity_median', 0.1)
        out_ellip = out_stats.get('ellipticity_median', 0.1)
        
        # Noise check: calculate relative noise (std / mean)
        ref_noise = ref_stats.get('bg_std', 1) / max(abs(ref_stats.get('bg_mean', 1)), 1)
        out_noise = out_stats.get('bg_std', 1) / max(abs(out_stats.get('bg_mean', 1)), 1)
        
        # 3. FWHM (Sharpness) (25 pts)
        # Unaligned stack with large dithers will have massive FWHM (>15px)
        if out_fwhm < ref_fwhm * 1.5:
            score += 25
            feedback_parts.append(f"Excellent sharpness (FWHM: {out_fwhm:.2f}px). Stars are aligned.")
        elif out_fwhm < ref_fwhm * 2.5:
            score += 10
            feedback_parts.append(f"Moderate sharpness (FWHM: {out_fwhm:.2f}px). Alignment may be imperfect.")
        else:
            feedback_parts.append(f"Poor sharpness (FWHM: {out_fwhm:.2f}px). Stars appear smeared/unaligned.")
            
        # 4. Ellipticity (20 pts)
        # Streaks from unaligned stacking have high ellipticity
        if out_ellip < 0.35:
            score += 20
            feedback_parts.append(f"Stars are round (Ellipticity: {out_ellip:.2f}). Good alignment.")
        elif out_ellip < 0.5:
            score += 10
            feedback_parts.append(f"Stars slightly elongated (Ellipticity: {out_ellip:.2f}).")
        else:
            feedback_parts.append(f"Stars highly elongated (Ellipticity: {out_ellip:.2f}).")
            
        # 5. Noise Reduction (10 pts)
        if out_noise < ref_noise * 0.95:
            score += 10
            feedback_parts.append("Background noise successfully reduced via stacking.")
        else:
            feedback_parts.append("Stack noise did not improve compared to single frame.")
            
    elif output_exists and not out_stats:
        feedback_parts.append("Could not detect stars in output (image might be completely smeared or blank).")

    # ------------------------------------------------------------------
    # VLM Trajectory Check (20 pts)
    # ------------------------------------------------------------------
    if query_vlm and 'sample_trajectory_frames' in env_info:
        frames = env_info['sample_trajectory_frames'](traj, n=5)
        if frames:
            try:
                vlm_resp = query_vlm(
                    prompt=VLM_ALIGNMENT_PROMPT,
                    images=frames
                )
                if vlm_resp and vlm_resp.get("success"):
                    parsed = vlm_resp.get("parsed", {})
                    if parsed.get("alignment_dialog_visible") or parsed.get("apertures_placed_for_alignment"):
                        score += 20
                        feedback_parts.append("VLM confirmed alignment tools were used.")
                    else:
                        feedback_parts.append("VLM did not detect clear use of alignment tools.")
            except Exception as e:
                logger.warning(f"VLM check failed: {e}")
                
    # Ensure score doesn't exceed 100
    score = min(100, score)
    
    # Pass criteria: Needs good score AND must not be a mere copy
    key_criteria_met = output_exists and valid_fits and not is_copy
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }