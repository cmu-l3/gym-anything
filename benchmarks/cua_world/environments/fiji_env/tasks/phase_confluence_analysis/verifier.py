#!/usr/bin/env python3
"""
Verifier for phase_confluence_analysis task.

Criteria:
1. Binary mask created (15 pts)
2. Report file created (15 pts)
3. Mask Quality (IoU vs Ground Truth) (40 pts)
   - 0.6+ IoU: Full points
   - 0.4-0.6 IoU: Partial points
4. Confluence Value Accuracy (30 pts)
   - Within tolerance of GT
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_phase_confluence_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_gt_val = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        copy_from_env("/tmp/gt_value.txt", temp_gt_val.name)
        
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
            
        with open(temp_gt_val.name, 'r') as f:
            gt_val_str = f.read().strip()
            gt_confluence = float(gt_val_str) if gt_val_str else 0.0
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load results: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        if os.path.exists(temp_gt_val.name):
            os.unlink(temp_gt_val.name)

    score = 0
    feedback = []

    # 1. Mask Existence (15 pts)
    if result.get("mask_exists") and result.get("mask_created_during_task"):
        score += 15
        feedback.append("Binary mask created.")
    elif result.get("mask_exists"):
        score += 5
        feedback.append("Mask exists but timestamp check failed.")
    else:
        feedback.append("No output mask found.")

    # 2. Report Existence (15 pts)
    if result.get("report_exists"):
        score += 15
        feedback.append("Report file created.")
    else:
        feedback.append("Report file missing.")

    # 3. Segmentation Quality (IoU) (40 pts)
    iou = result.get("iou_score", 0.0)
    if iou >= 0.6:
        score += 40
        feedback.append(f"Excellent segmentation (IoU: {iou:.2f}).")
    elif iou >= 0.4:
        score += 20
        feedback.append(f"Fair segmentation (IoU: {iou:.2f}).")
    elif iou > 0.1:
        score += 10
        feedback.append(f"Poor segmentation (IoU: {iou:.2f}).")
    else:
        feedback.append(f"Segmentation failed or mismatched (IoU: {iou:.2f}).")

    # 4. Confluence Value Accuracy (30 pts)
    try:
        reported_val = float(result.get("reported_value", -999))
        diff = abs(reported_val - gt_confluence)
        tolerance = task_info.get("metadata", {}).get("confluence_tolerance", 15.0)
        
        if reported_val == -999:
             feedback.append("Could not parse value from report.")
        elif diff <= tolerance:
            score += 30
            feedback.append(f"Reported value {reported_val}% is accurate (GT: {gt_confluence:.1f}%).")
        elif diff <= tolerance * 2:
            score += 15
            feedback.append(f"Reported value {reported_val}% is somewhat off (GT: {gt_confluence:.1f}%).")
        else:
            feedback.append(f"Reported value {reported_val}% is incorrect (GT: {gt_confluence:.1f}%).")
            
    except ValueError:
        feedback.append("Report content was not a valid number.")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }