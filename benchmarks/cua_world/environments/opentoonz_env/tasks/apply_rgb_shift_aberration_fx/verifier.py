#!/usr/bin/env python3
import json
import os
import sys
import tempfile
import logging
import numpy as np
import cv2

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def calculate_channel_offset(image_path):
    """
    Calculates the horizontal shift of the Red channel relative to the Green channel.
    Returns: (shift_x, correlation_score)
    Positive shift_x means Red is shifted to the RIGHT relative to Green.
    """
    try:
        # Load image
        img = cv2.imread(image_path)
        if img is None:
            return 0, 0.0

        # Split channels: OpenCV loads as BGR
        b, g, r = cv2.split(img)

        # dwanko_run is black lines on white/transparent.
        # Invert so lines are high intensity (bright) for correlation
        r_inv = 255 - r
        g_inv = 255 - g

        # Project to 1D (sum columns) to detect horizontal shift robustly
        r_proj = np.sum(r_inv, axis=0).astype(np.float32)
        g_proj = np.sum(g_inv, axis=0).astype(np.float32)

        # Normalize projections
        if np.max(r_proj) > 0: r_proj /= np.max(r_proj)
        if np.max(g_proj) > 0: g_proj /= np.max(g_proj)

        # Cross-correlation using numpy
        # "full" mode returns correlation at all lags
        correlation = np.correlate(r_proj, g_proj, mode='full')
        
        # Find index of maximum correlation
        # The center index corresponds to 0 lag
        lags = np.arange(len(correlation)) - (len(g_proj) - 1)
        max_idx = np.argmax(correlation)
        shift_x = lags[max_idx]
        
        # Calculate a confidence score (peak value)
        score = correlation[max_idx] / np.sum(r_proj**2)**0.5 / np.sum(g_proj**2)**0.5

        return shift_x, score

    except Exception as e:
        logger.error(f"Error calculating offset: {e}")
        return 0, 0.0

def verify_apply_rgb_shift_aberration_fx(traj, env_info, task_info):
    """
    Verifies that the agent applied a Red channel horizontal shift.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_frame_count = metadata.get('min_frame_count', 12)
    min_shift_px = metadata.get('min_shift_pixels', 5)

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Scoring Variables
    score = 0
    feedback = []
    
    # 2. Check File Existence and Count (20 pts)
    output_exists = result.get('output_exists', False)
    file_count = result.get('file_count', 0)
    files_new = result.get('files_created_during_task', False)
    
    if output_exists and file_count >= min_frame_count:
        score += 20
        feedback.append(f"Rendered {file_count} frames (Target: {min_frame_count}+)")
    elif output_exists:
        score += 10
        feedback.append(f"Rendered only {file_count} frames (Target: {min_frame_count}+)")
    else:
        feedback.append("No output files found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # 3. Check Anti-Gaming (Timestamp) (10 pts)
    if files_new:
        score += 10
        feedback.append("Files created during task session.")
    else:
        feedback.append("Warning: Files timestamp suggests pre-existing files.")

    # 4. Computer Vision Verification (70 pts total)
    sample_path = result.get('sample_file_path', '')
    if not sample_path:
        feedback.append("No sample file to analyze.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}
        
    # Copy the sample image to host
    temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        copy_from_env(sample_path, temp_img.name)
        
        # Analyze
        shift_x, conf = calculate_channel_offset(temp_img.name)
        
        logger.info(f"CV Analysis: Shift={shift_x}, Conf={conf}")
        
        # Scoring Logic based on CV
        
        # Detection threshold: Verify content is dwanko (high correlation)
        if conf < 0.3:
            feedback.append("Rendered content does not match expected line art structure.")
        else:
            score += 10 # Content looks valid
            
            # Shift Magnitude Check (40 pts)
            if abs(shift_x) >= min_shift_px:
                score += 40
                feedback.append(f"Significant channel separation detected ({abs(shift_x)}px).")
                
                # Direction Check (20 pts)
                # Task asks for Red shifted Right -> Shift should be Positive
                if shift_x > 0:
                    score += 20
                    feedback.append("Red channel shifted Right (Correct direction).")
                else:
                    feedback.append("Red channel shifted Left (Wrong direction).")
            else:
                feedback.append(f"Channel separation too small ({abs(shift_x)}px). Effect not visible.")

    except Exception as e:
        feedback.append(f"Image analysis failed: {e}")
    finally:
        if os.path.exists(temp_img.name):
            os.unlink(temp_img.name)

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }