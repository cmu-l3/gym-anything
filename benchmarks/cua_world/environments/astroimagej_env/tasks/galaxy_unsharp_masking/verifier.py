#!/usr/bin/env python3
"""
Verifier for galaxy_unsharp_masking task.

Multi-Criteria Verification:
1. File Existence & Timestamps (Prevent "do nothing")
2. Programmatic FITS Mathematics Check (Validates exact workflow execution)
3. VLM Trajectory Verification (Visual proof of Gaussian Blur & Image Calculator usage)
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_galaxy_unsharp_masking(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    mae_tolerance = metadata.get('mae_tolerance', 50.0)

    # 1. Retrieve the programmatic metrics computed by export_result.sh
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    math_success = result.get('math_success', False)
    
    # CRITERION 1: File check (15 points)
    if output_exists and file_created:
        score += 15
        feedback_parts.append("FITS output created correctly")
    elif output_exists:
        score += 5
        feedback_parts.append("Output exists but timestamp is incorrect")
    else:
        feedback_parts.append("Output file not found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    # CRITERION 2 & 3: Mathematical Image Validation (40 points)
    # math_success ensures the output is a valid FITS file with identical dimensions
    if math_success:
        score += 10
        mae_vs_gt = result.get('mae_vs_gt', float('inf'))
        mae_vs_orig = result.get('mae_vs_orig', 0.0)
        mae_vs_zeros = result.get('mae_vs_zeros', 0.0)
        
        # Verify the image isn't completely empty and isn't just an unmodified resave
        if mae_vs_zeros > 1.0 and mae_vs_orig > 1.0:
            # Check precision match with the programmatic high-pass ground truth
            # Because ImageJ's kernel differs slightly from SciPy's, MAE won't be exactly 0, but will be small
            if mae_vs_gt < mae_tolerance:
                score += 30
                feedback_parts.append(f"Subtraction logic perfectly executed (MAE vs Ground Truth: {mae_vs_gt:.2f})")
            elif mae_vs_gt < mae_vs_orig:
                score += 15  # Partial credit: math was modified in the right direction, maybe wrong radius
                feedback_parts.append(f"Subtraction detected but precision is off (MAE vs GT: {mae_vs_gt:.2f})")
            else:
                feedback_parts.append(f"Output array diverges heavily from expected math (MAE vs GT: {mae_vs_gt:.2f})")
        else:
            feedback_parts.append("Image appears completely blank or unmodified from original")
    else:
        error_msg = result.get('math_error', 'Unknown parsing error')
        feedback_parts.append(f"FITS math evaluation failed: {error_msg}")
        
    # CRITERION 4: Visual Trajectory Verification via VLM (45 points)
    # We want to see evidence that the user interacted with Gaussian Blur and Image Calculator
    try:
        frames = sample_trajectory_frames(traj, n=5)
        prompt = (
            "You are verifying a workflow in AstroImageJ. Look at these frames from a user session.\n"
            "Do you see visual evidence of BOTH of the following happening?\n"
            "1. The 'Gaussian Blur' dialog box being opened.\n"
            "2. The 'Image Calculator' dialog box being opened to subtract images.\n"
            "Answer simply 'Yes' if you see evidence of these workflow steps, or 'No' if they are missing."
        )
        
        vlm_response = query_vlm(images=frames, prompt=prompt)
        if vlm_response and "yes" in vlm_response.lower()[:15]:
            score += 45
            feedback_parts.append("VLM visual verification confirmed UI workflow steps")
        else:
            feedback_parts.append("VLM could not confirm Gaussian Blur / Image Calculator UI interaction")
            
    except Exception as e:
        logger.error(f"VLM verification error: {e}")
        feedback_parts.append("VLM visual verification failed to execute")

    # Determine overall pass
    # Must have >= 70 points AND a valid math logic subtraction
    key_criteria_met = file_created and math_success and (result.get('mae_vs_gt', float('inf')) < mae_tolerance)
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }