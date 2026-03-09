#!/usr/bin/env python3
"""
Verifier for dental_inventory_assessment task.

Verifies:
1. dental_inventory.txt exists and was created during the task.
2. Content matches the ground truth for present/missing teeth.
3. VLM trajectory verification: confirmed navigation of panoramic/axial views.
"""

import json
import os
import re
import tempfile
import logging
from typing import Dict, Any, List, Set

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_inventory_file(content: str) -> Dict[str, Set[int]]:
    """Parses the dental inventory text file."""
    present = set()
    missing = set()
    
    try:
        lines = content.split('\n')
        for line in lines:
            line = line.strip().lower()
            if "present teeth" in line:
                nums = re.findall(r'\d+', line)
                present.update(map(int, nums))
            elif "missing teeth" in line:
                nums = re.findall(r'\d+', line)
                missing.update(map(int, nums))
    except Exception as e:
        logger.error(f"Error parsing inventory file: {e}")
        
    return {"present": present, "missing": missing}

def calculate_f1(predicted: Set[int], actual: Set[int]) -> float:
    """Calculates F1 score for a set of teeth."""
    if not predicted and not actual:
        return 1.0
    
    tp = len(predicted.intersection(actual))
    fp = len(predicted - actual)
    fn = len(actual - predicted)
    
    precision = tp / (tp + fp) if (tp + fp) > 0 else 0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0
    
    if precision + recall == 0:
        return 0.0
        
    return 2 * (precision * recall) / (precision + recall)

def verify_dental_inventory(traj, env_info, task_info):
    """
    Verifies the dental inventory task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {})
    gt_present = set(ground_truth.get('present_teeth', []))
    gt_missing = set(ground_truth.get('missing_teeth', []))

    # Retrieve result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: In Windows env, path separators might need handling, 
        # but copy_from_env usually handles the source path string literally.
        # The export script saved to C:\workspace\tasks\...\task_result.json
        # We need the path mapping. Assuming standard unix-like path for the container mount 
        # or the copy_from_env handles windows paths if the agent is windows.
        # Based on env spec, the container path is /workspace/tasks/...
        copy_from_env("C:\\workspace\\tasks\\dental_inventory_assessment\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File Existence & Timing (10 pts)
    if result.get('file_exists') and result.get('file_created_during_task'):
        score += 10
        feedback_parts.append("Inventory file created successfully.")
    else:
        feedback_parts.append("Inventory file missing or old.")
        return {"passed": False, "score": 0, "feedback": "No output file generated."}

    # 2. Content Accuracy (60 pts)
    content = result.get('file_content', "")
    parsed = parse_inventory_file(content)
    
    # Check strict format compliance briefly
    if "DENTAL INVENTORY" in content and "Present teeth" in content:
        score += 5
    
    # Calculate accuracy
    f1_present = calculate_f1(parsed['present'], gt_present)
    f1_missing = calculate_f1(parsed['missing'], gt_missing)
    
    accuracy_score = (f1_present * 30) + (f1_missing * 25)
    score += accuracy_score
    
    feedback_parts.append(f"Accuracy - Present: {f1_present:.2f}, Missing: {f1_missing:.2f}")

    # 3. VLM Verification (30 pts)
    # Check if agent actually navigated the views
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Review this sequence of screenshots from Blue Sky Plan dental software.
    1. Does the user scroll through the views (axial, panoramic, or cross-sectional)?
    2. Is the "Tooth Chart" or "Teeth" panel visible/open at any point?
    3. Are there blue/colored markers appearing on the teeth in the views?
    
    Return JSON:
    {
        "navigation_occurred": boolean,
        "tooth_chart_opened": boolean,
        "markers_visible": boolean
    }
    """
    
    vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result.get("success"):
        data = vlm_result.get("parsed", {})
        if data.get("navigation_occurred"): vlm_score += 10
        if data.get("tooth_chart_opened"): vlm_score += 10
        if data.get("markers_visible"): vlm_score += 10
        
        score += vlm_score
        feedback_parts.append(f"Visual verification score: {vlm_score}/30")
    else:
        feedback_parts.append("Visual verification failed (VLM error).")

    # Final tally
    passed = score >= 60 and f1_present > 0.6 and f1_missing > 0.6
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }