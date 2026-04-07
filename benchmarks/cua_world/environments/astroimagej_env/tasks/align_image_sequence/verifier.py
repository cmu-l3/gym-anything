#!/usr/bin/env python3
"""
Verifier for align_image_sequence task.

Uses MULTIPLE INDEPENDENT SIGNALS for verification:
1. File verification: Output sequence must exist and be strictly created AFTER task start.
2. OpenCV phase correlation: Mathematically guarantees stars have been shifted to identical coordinates.
3. Anti-Gaming logic: Tests whether output arrays are identically cloned (which evades shift checks).
4. VLM Verification: Analyzes trajectory screenshots to ensure AstroImageJ tools were actually utilized.
"""

import os
import json
import tempfile
import logging
import numpy as np
import cv2
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_align_image_sequence(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_count = metadata.get('expected_file_count', 10)
    coarse_tol = metadata.get('drift_tolerance_coarse', 5.0)
    perfect_tol = metadata.get('drift_tolerance_perfect', 2.0)

    feedback_parts = []
    score = 0

    # 1. Retrieve the task result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    file_count = result.get('file_count', 0)
    new_file_count = result.get('new_file_count', 0)
    arrays_extracted = result.get('arrays_extracted', False)
    app_was_running = result.get('app_was_running', False)

    # 2. Check File Outputs & Anti-Gaming timestamp logic (20 points)
    if file_count >= expected_count:
        if new_file_count >= expected_count:
            score += 20
            feedback_parts.append(f"{expected_count} new output files found")
        else:
            score += 10
            feedback_parts.append(f"{file_count} files found, but only {new_file_count} created during task")
    elif file_count > 0:
        score += 5
        feedback_parts.append(f"Incomplete output: {file_count} files found")
    else:
        feedback_parts.append("No output FITS files found in the processed directory")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # 3. Check App State (10 points)
    if app_was_running:
        score += 10

    # 4. Check Arrays / Image Alignment (40 points)
    drift = float('inf')
    identical_arrays = False
    
    if arrays_extracted:
        temp_first = tempfile.NamedTemporaryFile(delete=False, suffix='.npy')
        temp_last = tempfile.NamedTemporaryFile(delete=False, suffix='.npy')
        try:
            copy_from_env("/tmp/aligned_first.npy", temp_first.name)
            copy_from_env("/tmp/aligned_last.npy", temp_last.name)
            
            arr1 = np.load(temp_first.name).astype(np.float32)
            arr2 = np.load(temp_last.name).astype(np.float32)
            
            # Anti-gaming: Ensure agent didn't just copy frame_00.fits 10 times to cheat phase correlation
            if np.allclose(arr1, arr2, atol=1e-5):
                identical_arrays = True
                feedback_parts.append("FAIL: Output arrays are perfectly identical (possible duplication/gaming)")
            else:
                # Calculate alignment accuracy using Sub-pixel Phase Correlation
                norm1 = cv2.normalize(arr1, None, 0, 1, cv2.NORM_MINMAX)
                norm2 = cv2.normalize(arr2, None, 0, 1, cv2.NORM_MINMAX)
                
                # Apply hanning window to mitigate boundary issues triggered by the shift
                hanning = cv2.createHanningWindow(norm1.shape[::-1], cv2.CV_32F)
                (dx, dy), response = cv2.phaseCorrelate(norm1, norm2, window=hanning)
                
                drift = np.sqrt(dx**2 + dy**2)
                logger.info(f"Phase correlation shift: dx={dx:.2f}, dy={dy:.2f}, magnitude={drift:.2f} px")
                
                if drift <= perfect_tol:
                    score += 40
                    feedback_parts.append(f"Excellent alignment (drift: {drift:.2f}px)")
                elif drift <= coarse_tol:
                    score += 25
                    feedback_parts.append(f"Coarse alignment achieved (drift: {drift:.2f}px)")
                else:
                    feedback_parts.append(f"Images remain unaligned (drift: {drift:.2f}px)")
                    
        except Exception as e:
            feedback_parts.append(f"Array verification error: {e}")
            logger.error(f"Error checking arrays: {e}")
        finally:
            if os.path.exists(temp_first.name): os.unlink(temp_first.name)
            if os.path.exists(temp_last.name): os.unlink(temp_last.name)
    else:
        feedback_parts.append("Could not extract image arrays for mathematical verification")

    # 5. VLM Verification (30 points)
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = (
            "The agent was asked to align a drifting sequence of astronomical images using AstroImageJ. "
            "Please review these frames from the session.\n"
            "1. Did the agent open the 'Align stack using WCS or apertures' dialog?\n"
            "2. Did the agent click on a reference star to align the sequence?\n"
            "3. Is there evidence that the stack was saved as an image sequence?\n"
            "Respond strictly with YES if there is visual evidence of the alignment workflow occurring, otherwise NO."
        )
        
        vlm_response = query_vlm(images=frames + [final], prompt=prompt).lower()
        
        if "yes" in vlm_response:
            score += 30
            feedback_parts.append("VLM visually confirmed alignment workflow")
        else:
            feedback_parts.append("VLM did not observe correct sequence alignment tools")
    except Exception as e:
        logger.error(f"VLM Error: {e}")
        score += 15
        feedback_parts.append("VLM verification skipped/errored")

    # Tally results against passing criteria
    key_criteria_met = (new_file_count >= expected_count) and (drift <= coarse_tol) and not identical_arrays
    passed = (score >= 60) and key_criteria_met
    
    # Cap score severely if gaming is detected
    if identical_arrays:
        passed = False
        score = min(score, 30)
        
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }