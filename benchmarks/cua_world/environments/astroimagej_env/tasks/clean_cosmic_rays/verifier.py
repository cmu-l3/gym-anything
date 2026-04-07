#!/usr/bin/env python3
"""
Verifier for clean_cosmic_rays task in AstroImageJ.

VERIFICATION STRATEGY:
1. File Existence & Timestamps (Prevent "do nothing" or gaming)
2. FITS programmatic validation (Processed securely inside the container)
3. Action Verification: Image math correctness (Mask = Orig - Cleaned)
4. Quality Verification: Preserved stellar structures (Correlation & Pixel Change limit)
5. VLM Trajectory Verification: Visually check usage of dialogs
"""

import os
import json
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_clean_cosmic_rays(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    metadata = task_info.get('metadata', {})
    max_pixels_changed_pct = metadata.get('max_pixels_changed_pct', 0.15)
    min_correlation = metadata.get('min_correlation', 0.90)

    # 1. Retrieve the exported JSON result from the container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    clean_created = result.get('clean_created', 'false')
    mask_created = result.get('mask_created', 'false')
    metrics = result.get('fits_metrics', {})
    
    # Check if files were properly created during the task
    if clean_created == 'true':
        score += 10
        feedback_parts.append("Cleaned FITS created")
    elif clean_created == 'false_old':
        feedback_parts.append("Cleaned FITS is stale (not created during task)")
    else:
        feedback_parts.append("Cleaned FITS missing")

    if mask_created == 'true':
        score += 10
        feedback_parts.append("Mask FITS created")
    elif mask_created == 'false_old':
        feedback_parts.append("Mask FITS is stale (not created during task)")
    else:
        feedback_parts.append("Mask FITS missing")

    # Early exit if files missing
    if clean_created != 'true' or mask_created != 'true':
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # FITS Analysis Verification
    if metrics.get("error"):
        feedback_parts.append(f"FITS Analysis Error: {metrics.get('error')}")
    else:
        # Check if they actually applied a filter
        if metrics.get("clean_differs_from_orig", False):
            score += 15
            feedback_parts.append("Filtering applied")
        else:
            feedback_parts.append("Cleaned image is identical to original (No filter applied)")
            
        # Check if the mask is mathematically correct (Orig - Clean)
        if metrics.get("math_correct", False):
            score += 25
            feedback_parts.append("Image math correct (Mask = Orig - Clean)")
        else:
            feedback_parts.append(f"Image math incorrect (MAE: {metrics.get('math_mae', 'unknown'):.2f})")
            
        # Check signal preservation
        pct_changed = metrics.get("pct_pixels_changed", 1.0)
        corr = metrics.get("correlation", 0.0)
        
        if pct_changed < max_pixels_changed_pct and corr > min_correlation:
            score += 20
            feedback_parts.append(f"Signal preserved (Changed: {pct_changed:.1%}, Corr: {corr:.3f})")
        else:
            feedback_parts.append(f"Signal degraded (Changed: {pct_changed:.1%}, Corr: {corr:.3f})")

    # VLM Verification: Ensure the agent used the UI dialogs
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = (
            "You are verifying an astronomy task in AstroImageJ. "
            "Did the user's workflow involve opening an outlier rejection / noise reduction tool "
            "(like 'Remove Outliers...' or 'Despeckle') AND opening the 'Image Calculator' dialog to subtract images? "
            "Answer 'Yes' if there is evidence of using these tools in the screenshots, otherwise 'No'."
        )
        
        vlm_result = query_vlm(images=frames + [final], prompt=prompt).strip().lower()
        if 'yes' in vlm_result:
            score += 20
            feedback_parts.append("VLM verified UI usage")
        else:
            feedback_parts.append("VLM did not detect correct UI dialog usage")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        feedback_parts.append("VLM check bypassed")

    # Final Evaluation
    # Must achieve at least 70 to pass, proving they created files, used math correctly, and preserved stars.
    key_criteria_met = (
        clean_created == 'true' and 
        mask_created == 'true' and 
        metrics.get("clean_differs_from_orig", False) and 
        metrics.get("math_correct", False)
    )
    
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }