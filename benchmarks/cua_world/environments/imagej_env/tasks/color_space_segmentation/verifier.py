#!/usr/bin/env python3
"""
Verifier for Color-Based Segmentation task.
Uses OpenCV to generate Ground Truth from the reference image and compares it with Agent output.
"""

import json
import os
import tempfile
import logging
import cv2
import numpy as np
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_color_segmentation(traj, env_info, task_info):
    """
    Verify the green pepper segmentation mask.
    
    Scoring Criteria:
    1. File Created (20 pts)
    2. File is Binary Mask (10 pts)
    3. Intersection over Union (IoU) with Green Pepper > 0.5 (30 pts)
    4. Exclusion of Red Pepper (overlap < 10%) (20 pts)
    5. Overall Dice Coefficient > 0.6 (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup temp files
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_mask_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
    temp_ref_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
    
    score = 0
    feedback = []
    
    try:
        # 1. Load Task Result Metadata
        copy_from_env("/tmp/task_result.json", temp_result_json)
        with open(temp_result_json, 'r') as f:
            result_data = json.load(f)
            
        output_exists = result_data.get("output_exists", False)
        created_during_task = result_data.get("file_created_during_task", False)
        
        if not output_exists:
            return {"passed": False, "score": 0, "feedback": "Output mask file not found."}
        
        if not created_during_task:
            feedback.append("Warning: Output file timestamp is older than task start.")
            # We don't fail immediately but penalize if strictly enforcing
            
        score += 20
        feedback.append("Output file created.")
        
        # 2. Retrieve Images
        output_path = result_data.get("output_path")
        ref_path = result_data.get("reference_path")
        
        copy_from_env(output_path, temp_mask_img)
        copy_from_env(ref_path, temp_ref_img)
        
        # Load images using OpenCV
        agent_mask = cv2.imread(temp_mask_img, cv2.IMREAD_GRAYSCALE)
        ref_img = cv2.imread(temp_ref_img)
        
        if agent_mask is None:
            return {"passed": False, "score": score, "feedback": "Output file is not a valid image."}
        if ref_img is None:
            # Fallback if ref image capture failed - try standard peppers from memory/web?
            # For now, fail gracefully or skip GT check
            return {"passed": False, "score": score, "feedback": "Reference image missing, cannot verify accuracy."}

        # Resize agent mask to match reference if needed (robustness)
        if agent_mask.shape != ref_img.shape[:2]:
            agent_mask = cv2.resize(agent_mask, (ref_img.shape[1], ref_img.shape[0]), interpolation=cv2.INTER_NEAREST)

        # 3. Check Binary Nature (10 pts)
        unique_values = np.unique(agent_mask)
        if len(unique_values) > 2:
            feedback.append(f"Image is not strictly binary (has {len(unique_values)} values). Thresholding at 127.")
            _, agent_binary = cv2.threshold(agent_mask, 127, 255, cv2.THRESH_BINARY)
            score += 5 # Partial credit
        else:
            agent_binary = agent_mask
            score += 10
            feedback.append("Image is a valid binary mask.")

        # Normalize to 0/1 boolean
        agent_bool = agent_binary > 127
        
        # 4. Generate Ground Truth (Green vs Red)
        hsv_ref = cv2.cvtColor(ref_img, cv2.COLOR_BGR2HSV)
        
        # Green Pepper HSV range (approximate for standard 'Peppers' image)
        # H: 35-85 (in 0-180 scale), S: >50, V: >50
        lower_green = np.array([35, 40, 40])
        upper_green = np.array([90, 255, 255])
        gt_green_mask = cv2.inRange(hsv_ref, lower_green, upper_green)
        gt_green_bool = gt_green_mask > 0
        
        # Red Pepper HSV range (centers around 0/180)
        # Two ranges: 0-15 and 160-180
        lower_red1 = np.array([0, 50, 50])
        upper_red1 = np.array([15, 255, 255])
        lower_red2 = np.array([160, 50, 50])
        upper_red2 = np.array([180, 255, 255])
        gt_red_mask = cv2.bitwise_or(
            cv2.inRange(hsv_ref, lower_red1, upper_red1),
            cv2.inRange(hsv_ref, lower_red2, upper_red2)
        )
        gt_red_bool = gt_red_mask > 0

        # 5. Calculate Metrics
        
        # Intersection over Union for Green
        intersection = np.logical_and(agent_bool, gt_green_bool).sum()
        union = np.logical_or(agent_bool, gt_green_bool).sum()
        iou = intersection / union if union > 0 else 0.0
        
        # Dice Coefficient for Green
        dice = 2 * intersection / (agent_bool.sum() + gt_green_bool.sum()) if (agent_bool.sum() + gt_green_bool.sum()) > 0 else 0.0
        
        # Red Overlap (False Positives in Red Region)
        red_intersection = np.logical_and(agent_bool, gt_red_bool).sum()
        red_area = gt_red_bool.sum()
        red_overlap_ratio = red_intersection / red_area if red_area > 0 else 0.0
        
        # 6. Score Logic
        
        # Green IoU (30 pts)
        if iou > 0.5:
            score += 30
            feedback.append(f"Excellent Green Pepper IoU: {iou:.2f}")
        elif iou > 0.3:
            score += 15
            feedback.append(f"Acceptable Green Pepper IoU: {iou:.2f}")
        else:
            feedback.append(f"Poor Green Pepper IoU: {iou:.2f}. Mask may be missing parts or too messy.")

        # Red Exclusion (20 pts)
        if red_overlap_ratio < 0.1:
            score += 20
            feedback.append(f"Successfully excluded Red Pepper (Overlap: {red_overlap_ratio:.2f})")
        elif red_overlap_ratio < 0.3:
            score += 10
            feedback.append(f"Partially excluded Red Pepper (Overlap: {red_overlap_ratio:.2f})")
        else:
            feedback.append(f"Failed to exclude Red Pepper (Overlap: {red_overlap_ratio:.2f}). Check color thresholds.")

        # Dice Check (20 pts)
        if dice > 0.6:
            score += 20
            feedback.append(f"High Dice Coefficient: {dice:.2f}")
        elif dice > 0.4:
            score += 10
            feedback.append(f"Moderate Dice Coefficient: {dice:.2f}")
            
        passed = score >= 60
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback),
            "details": {
                "iou": float(iou),
                "dice": float(dice),
                "red_overlap": float(red_overlap_ratio),
                "mask_exists": True
            }
        }
        
    except Exception as e:
        logger.exception("Verification failed with error")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
        
    finally:
        # Cleanup
        for f in [temp_result_json, temp_mask_img, temp_ref_img]:
            if os.path.exists(f):
                os.unlink(f)