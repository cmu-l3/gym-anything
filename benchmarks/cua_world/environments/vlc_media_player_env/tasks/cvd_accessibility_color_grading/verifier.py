#!/usr/bin/env python3
"""
Verifier for cvd_accessibility_color_grading task.

Performs robust image processing checks on frames extracted from the agent's video outputs.
"""

import json
import os
import tempfile
import logging
import cv2
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cvd_accessibility_color_grading(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    # Create temporary directory to hold pulled files
    with tempfile.TemporaryDirectory() as temp_dir:
        # Pull the task result JSON
        result_json_path = os.path.join(temp_dir, 'task_result.json')
        try:
            copy_from_env("/tmp/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}

        # --- Check 1: File Existence & Anti-Gaming (10 points) ---
        cvd_exists = result.get("cvd_blue_exists", False)
        cvd_new = result.get("cvd_blue_created_during_task", False)
        bw_exists = result.get("high_contrast_bw_exists", False)
        bw_new = result.get("high_contrast_bw_created_during_task", False)

        if cvd_exists and bw_exists:
            if cvd_new and bw_new:
                score += 10
                feedback_parts.append("Output videos successfully generated")
            else:
                score += 5
                feedback_parts.append("Videos exist but may not have been created during task")
        else:
            feedback_parts.append("Missing one or both expected output videos")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

        # Pull extracted frames
        orig_frame_path = os.path.join(temp_dir, 'orig_frame.png')
        cvd_frame_path = os.path.join(temp_dir, 'cvd_frame.png')
        bw_frame_path = os.path.join(temp_dir, 'bw_frame.png')
        
        try:
            copy_from_env("/tmp/cvd_frames/orig_frame.png", orig_frame_path)
            copy_from_env("/tmp/cvd_frames/cvd_frame.png", cvd_frame_path)
            copy_from_env("/tmp/cvd_frames/bw_frame.png", bw_frame_path)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to pull extracted video frames: {e}"}

        # Load images via OpenCV (BGR format)
        orig_img = cv2.imread(orig_frame_path)
        cvd_img = cv2.imread(cvd_frame_path)
        bw_img = cv2.imread(bw_frame_path)

        if orig_img is None or cvd_img is None or bw_img is None:
            feedback_parts.append("Error reading video frame data. Videos may be corrupted or invalid.")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

        # --- Check 2: Structural Similarity / Anti-Gaming (20 points) ---
        # Ensures the agent didn't just replace the video with a solid color box
        orig_gray = cv2.cvtColor(orig_img, cv2.COLOR_BGR2GRAY)
        cvd_gray = cv2.cvtColor(cvd_img, cv2.COLOR_BGR2GRAY)
        bw_gray = cv2.cvtColor(bw_img, cv2.COLOR_BGR2GRAY)
        
        # Calculate correlation coefficient between flat arrays as a proxy for structural similarity
        def corr_coeff(img1, img2):
            return np.corrcoef(img1.flatten(), img2.flatten())[0, 1]
            
        cvd_structure = corr_coeff(orig_gray, cvd_gray)
        bw_structure = corr_coeff(orig_gray, bw_gray)
        
        if cvd_structure > 0.85 and bw_structure > 0.85:
            score += 20
            feedback_parts.append("Structural integrity preserved (SSIM pass)")
        else:
            feedback_parts.append(f"Structural failure (Agent likely used fake video/solid color). CVD corr: {cvd_structure:.2f}, BW corr: {bw_structure:.2f}")

        # --- Check 3: Red-Blue Channel Swap (25 points) ---
        # The region of interest (beaker) is at x=300:554, y=150:400
        # In the original frame at t=8s, the beaker is RED.
        roi_orig = orig_img[150:400, 300:554]
        roi_cvd = cvd_img[150:400, 300:554]
        
        # cv2 uses BGR
        orig_b_mean, _, orig_r_mean = cv2.split(roi_orig)
        cvd_b_mean, _, cvd_r_mean = cv2.split(roi_cvd)
        
        orig_r_val = orig_r_mean.mean()
        orig_b_val = orig_b_mean.mean()
        cvd_r_val = cvd_r_mean.mean()
        cvd_b_val = cvd_b_mean.mean()
        
        # Original should be distinctly red
        if orig_r_val > orig_b_val * 2:
            # CVD should be distinctly blue, and R/B values should be effectively swapped
            if cvd_b_val > cvd_r_val * 2 and cvd_b_val > 100:
                score += 25
                feedback_parts.append("Red-Blue channels perfectly swapped (CVD Dalonization passed)")
            elif cvd_b_val > cvd_r_val:
                score += 10
                feedback_parts.append("Red-Blue channels partially swapped, lacking precision")
            else:
                feedback_parts.append("Red-Blue channel swap failed (Reaction is not blue)")
        else:
            feedback_parts.append("Error in source video extraction (Beaker not red)")

        # --- Check 4: True Grayscale (15 points) ---
        # Variance between R, G, B channels should be near zero for every pixel in the BW image
        b_bw, g_bw, r_bw = cv2.split(bw_img)
        diff_bg = np.abs(b_bw.astype(int) - g_bw.astype(int)).mean()
        diff_gr = np.abs(g_bw.astype(int) - r_bw.astype(int)).mean()
        
        if diff_bg < 2.0 and diff_gr < 2.0:
            score += 15
            feedback_parts.append("Monochrome output is perfectly grayscale")
        else:
            feedback_parts.append(f"Monochrome output contains color artifacts (variance > threshold)")

        # --- Check 5: 50% Contrast Enhancement (15 points) ---
        # RMS contrast is the standard deviation of the pixel intensities
        orig_contrast = np.std(orig_gray)
        bw_contrast = np.std(bw_gray)
        
        if orig_contrast > 0:
            contrast_ratio = bw_contrast / orig_contrast
            if 1.35 <= contrast_ratio <= 1.65:
                score += 15
                feedback_parts.append(f"Contrast enhancement precise (Ratio: {contrast_ratio:.2f}x)")
            elif 1.1 <= contrast_ratio <= 1.9:
                score += 7
                feedback_parts.append(f"Contrast enhancement partial/imprecise (Ratio: {contrast_ratio:.2f}x)")
            else:
                feedback_parts.append(f"Contrast enhancement failed (Ratio: {contrast_ratio:.2f}x vs 1.50x expected)")

        # --- Check 6: Compliance Report (15 points) ---
        if result.get("report_exists", False):
            report_path = os.path.join(temp_dir, 'remediation_report.json')
            try:
                copy_from_env("/tmp/cvd_frames/remediation_report.json", report_path)
                with open(report_path, 'r') as f:
                    report_data = json.load(f)
                    
                # Check for some evidence of the required fields
                report_str = json.dumps(report_data).lower()
                if "titration_cvd_blue.mp4" in report_str and "titration_high_contrast_bw.mp4" in report_str:
                    score += 15
                    feedback_parts.append("Compliance report is valid JSON and contains required deliverables")
                else:
                    score += 5
                    feedback_parts.append("Compliance report exists but missing required filenames")
            except Exception:
                feedback_parts.append("Compliance report is not valid JSON")
        else:
            feedback_parts.append("Compliance report missing")

        # Determine pass/fail
        passed = score >= 70 and cvd_structure > 0.85

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }