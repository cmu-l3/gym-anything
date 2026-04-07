#!/usr/bin/env python3
"""
Verifier for generate_walk_pose_sheet task.

Verifies that:
1. Output PNG exists and was created during the task.
2. Dimensions are 1920x1080.
3. Content contains 3 distinct character poses (blobs) arranged horizontally.

Scoring:
- File exists & newer: 20 pts
- Resolution correct: 10 pts
- CV: 3 Distinct objects detected: 40 pts
- CV: Objects arranged horizontally: 30 pts
"""

import json
import tempfile
import os
import logging
import sys

# Try imports for image processing
try:
    import cv2
    import numpy as np
    CV_AVAILABLE = True
except ImportError:
    CV_AVAILABLE = False

try:
    from PIL import Image
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pose_sheet(traj, env_info, task_info):
    """Verify the pose sheet contains 3 distinct poses side-by-side."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_width = metadata.get('expected_width', 1920)
    expected_height = metadata.get('expected_height', 1080)
    expected_blobs = metadata.get('min_blobs', 3)

    # Copy result JSON
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
    
    # 1. File Existence & Metadata (30 pts max)
    file_exists = result.get('file_exists', False)
    file_newer = result.get('file_newer_than_start', False)
    img_width = result.get('image_width', 0)
    img_height = result.get('image_height', 0)
    
    if file_exists and file_newer:
        score += 20
        feedback_parts.append("Output file created")
    elif file_exists:
        score += 10
        feedback_parts.append("Output file exists (but old timestamp?)")
    else:
        feedback_parts.append("No output file found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    if img_width == expected_width and img_height == expected_height:
        score += 10
        feedback_parts.append("Resolution correct")
    else:
        feedback_parts.append(f"Wrong resolution: {img_width}x{img_height}")

    # 2. Image Content Analysis (70 pts max)
    # Copy the image file for analysis
    temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    img_path_in_env = result.get('file_path')
    
    analysis_success = False
    blob_count = 0
    is_horizontal = False
    
    if img_path_in_env and CV_AVAILABLE:
        try:
            copy_from_env(img_path_in_env, temp_img.name)
            
            # Read image using OpenCV
            img = cv2.imread(temp_img.name)
            if img is not None:
                # Convert to grayscale
                gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
                
                # Check if image is empty/blank
                if np.std(gray) < 5:
                    feedback_parts.append("Image appears blank")
                else:
                    # Thresholding
                    # Assume white background or transparent converted to black/white
                    # Invert if background is light
                    mean_val = np.mean(gray)
                    if mean_val > 200: # Light background
                        _, thresh = cv2.threshold(gray, 240, 255, cv2.THRESH_BINARY_INV)
                    else: # Dark background
                        _, thresh = cv2.threshold(gray, 10, 255, cv2.THRESH_BINARY)
                        
                    # Find contours
                    contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
                    
                    # Filter small noise
                    min_area = (img.shape[0] * img.shape[1]) * 0.005 # 0.5% of total area
                    valid_contours = [c for c in contours if cv2.contourArea(c) > min_area]
                    
                    blob_count = len(valid_contours)
                    analysis_success = True
                    
                    # Check horizontal distribution
                    if blob_count >= 2:
                        centroids_x = []
                        for c in valid_contours:
                            M = cv2.moments(c)
                            if M["m00"] != 0:
                                centroids_x.append(int(M["m10"] / M["m00"]))
                        
                        centroids_x.sort()
                        # Check spread
                        spread = centroids_x[-1] - centroids_x[0]
                        if spread > (img.shape[1] * 0.3): # Spread covers at least 30% of width
                            is_horizontal = True

        except Exception as e:
            feedback_parts.append(f"CV Analysis failed: {e}")
    
    # Clean up temp image
    if os.path.exists(temp_img.name):
        os.unlink(temp_img.name)

    # Scoring based on analysis
    if analysis_success:
        if blob_count == expected_blobs:
            score += 40
            feedback_parts.append(f"Correctly found {blob_count} poses")
        elif blob_count >= 2:
            score += 20
            feedback_parts.append(f"Found {blob_count} poses (expected {expected_blobs})")
        else:
            feedback_parts.append(f"Found {blob_count} poses (too few)")
            
        if is_horizontal:
            score += 30
            feedback_parts.append("Poses arranged horizontally")
        elif blob_count >= 2:
            feedback_parts.append("Poses not clearly distributed horizontally")

    # Fallback VLM check if CV failed or gave ambiguous results
    # (Optional but good for robustness)
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }