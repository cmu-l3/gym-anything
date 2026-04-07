#!/usr/bin/env python3
"""Verifier for technical_manual_asset_prep task.

Verifies:
1. Simulated Pulse Oximeter is running.
2. Full screenshot exists and was created during task.
3. Final asset exists, was created during task, and is:
   - Cropped (significantly smaller than full screen)
   - Grayscale (no color saturation)
   - Valid aspect ratio (waveform strip)
"""

import json
import os
import tempfile
import logging
import numpy as np
import cv2

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_technical_manual_asset_prep(traj, env_info, task_info):
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Load Result JSON
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

    score = 0
    feedback_parts = []
    
    task_start = result.get('task_start_timestamp', 0)
    
    # 1. Check Pulse Oximeter Device (20 pts)
    pulse_ox_running = result.get('pulse_ox_running', False)
    if pulse_ox_running:
        score += 20
        feedback_parts.append("Pulse Oximeter is running")
    else:
        feedback_parts.append("Pulse Oximeter window not found")

    # 2. Check Full Capture (10 pts)
    full_exists = result.get('full_capture_exists', False)
    full_mtime = result.get('full_capture_mtime', 0)
    
    full_img_path = None
    if full_exists and int(full_mtime) > task_start:
        score += 10
        feedback_parts.append("Full screenshot captured")
        
        # Copy full image for analysis dimensions
        try:
            temp_full = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env(result['full_capture_path'], temp_full.name)
            full_img_path = temp_full.name
        except:
            feedback_parts.append("Warning: Could not copy full screenshot for analysis")
    else:
        feedback_parts.append("Full screenshot missing or old")

    # 3. Check Final Asset Existence (10 pts)
    asset_exists = result.get('final_asset_exists', False)
    asset_mtime = result.get('final_asset_mtime', 0)
    
    asset_img_path = None
    if asset_exists and int(asset_mtime) > task_start:
        score += 10
        feedback_parts.append("Final asset file created")
        
        # Copy asset for detailed analysis
        try:
            temp_asset = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env(result['final_asset_path'], temp_asset.name)
            asset_img_path = temp_asset.name
        except:
            feedback_parts.append("Error: Could not copy final asset for analysis")
    else:
        feedback_parts.append("Final asset missing or old")

    # Image Analysis (if files exist)
    if full_img_path and asset_img_path:
        try:
            full_img = cv2.imread(full_img_path)
            asset_img = cv2.imread(asset_img_path)

            if full_img is None or asset_img is None:
                raise ValueError("Could not decode images")

            full_h, full_w = full_img.shape[:2]
            asset_h, asset_w = asset_img.shape[:2]
            
            full_area = full_h * full_w
            asset_area = asset_h * asset_w

            # 4. Check Cropping (20 pts)
            # Asset should be significantly smaller than full screen (e.g., < 25% area)
            # OR dimensions should be different enough
            if asset_area < (full_area * 0.4):
                score += 20
                feedback_parts.append(f"Image cropped successfully ({int(asset_area/full_area*100)}% of original)")
            elif asset_w < full_w or asset_h < full_h:
                score += 10 # Partial credit if cropped but still large
                feedback_parts.append("Image cropped somewhat")
            else:
                feedback_parts.append("Image does not appear cropped (same size as full screen)")

            # 5. Check Grayscale (20 pts)
            # Convert to HSV, check Saturation channel
            hsv_asset = cv2.cvtColor(asset_img, cv2.COLOR_BGR2HSV)
            saturation = hsv_asset[:, :, 1]
            mean_sat = np.mean(saturation)
            
            # Allow very small saturation due to compression artifacts, but basically 0
            if mean_sat < 5.0:
                score += 20
                feedback_parts.append("Image is grayscale")
            else:
                feedback_parts.append(f"Image contains color (Mean Saturation: {mean_sat:.1f})")

            # 6. Check Aspect Ratio (10 pts)
            # Waveforms are strips, so Width should be > Height (Landscape)
            aspect = asset_w / asset_h
            if aspect > 1.5:
                score += 10
                feedback_parts.append(f"Valid aspect ratio ({aspect:.1f})")
            else:
                feedback_parts.append(f"Invalid aspect ratio ({aspect:.1f}) - expected landscape strip")

            # 7. Check Content/Entropy (10 pts)
            # Ensure it's not a black/white box
            gray_asset = cv2.cvtColor(asset_img, cv2.COLOR_BGR2GRAY)
            std_dev = np.std(gray_asset)
            if std_dev > 5:
                score += 10
                feedback_parts.append("Image contains visual data")
            else:
                feedback_parts.append("Image appears blank/solid color")

        except Exception as e:
            feedback_parts.append(f"Image analysis failed: {str(e)}")
            # Cleanup
            if full_img_path and os.path.exists(full_img_path): os.unlink(full_img_path)
            if asset_img_path and os.path.exists(asset_img_path): os.unlink(asset_img_path)

    passed = score >= 60 and pulse_ox_running

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }