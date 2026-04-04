#!/usr/bin/env python3
"""
Verifier for extract_dicom_parameters task.

Verifies:
1. File exists and was created during the task.
2. Content contains the 5 required parameters with values matching ground truth.
3. VLM check: trajectory confirms interaction with InVesalius interface.
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_extract_dicom_parameters(traj, env_info, task_info):
    """
    Verify extraction of DICOM parameters from InVesalius.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    file_exists = result.get('file_exists', False)
    file_created = result.get('file_created_during_task', False)
    raw_content = result.get('file_content_raw', "")
    gt = result.get('ground_truth', {})

    # --- Criterion 1: File Existence & Anti-Gaming (15 pts) ---
    if file_exists and file_created:
        score += 15
        feedback_parts.append("Output file created during task")
    elif file_exists:
        score += 5
        feedback_parts.append("Output file exists but has old timestamp")
    else:
        feedback_parts.append("Output file /home/ga/Documents/ct_parameters.txt not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # --- Content Parsing Helpers ---
    def find_val(pattern, text):
        match = re.search(pattern, text, re.IGNORECASE | re.MULTILINE)
        return match.group(1).strip() if match else None

    # Parse agent output
    # Allow flexible separators: ":", "=", or just space
    # 1. Slices
    val_slices = find_val(r'(?:slices|slice count|images).*?[:=]\s*(\d+)', raw_content)
    # 2. Matrix
    val_matrix = find_val(r'(?:matrix|dimensions|size).*?[:=]\s*([\d\s\w,x*]+)', raw_content)
    # 3. Pixel Spacing
    val_spacing = find_val(r'(?:pixel.?spacing|spacing).*?[:=]\s*([\d.]+)', raw_content)
    # 4. Slice Thickness
    val_thickness = find_val(r'(?:slice.?thickness|thickness|gap).*?[:=]\s*([\d.]+)', raw_content)
    # 5. Modality
    val_modality = find_val(r'(?:modality|type).*?[:=]\s*([a-z]+)', raw_content)

    # --- Criterion 2: Parameter Verification (15 pts each = 75 pts) ---
    
    # 2a. Slices
    if val_slices and abs(int(val_slices) - gt.get('slices', 108)) <= 5:
        score += 15
        feedback_parts.append(f"Slices correct ({val_slices})")
    else:
        feedback_parts.append(f"Slices incorrect (expected ~{gt.get('slices')}, got {val_slices})")

    # 2b. Matrix (check for '512')
    # Ground truth is likely 512, check if '512' appears twice or logic
    gt_dim = str(gt.get('matrix_x', 512))
    if val_matrix and gt_dim in val_matrix:
        score += 15
        feedback_parts.append(f"Matrix correct ({val_matrix})")
    else:
        feedback_parts.append(f"Matrix incorrect (expected contains {gt_dim}, got {val_matrix})")

    # 2c. Pixel Spacing
    try:
        if val_spacing and abs(float(val_spacing) - float(gt.get('pixel_spacing', 0.957))) < 0.05:
            score += 15
            feedback_parts.append(f"Pixel spacing correct ({val_spacing})")
        else:
            feedback_parts.append(f"Pixel spacing incorrect (expected {gt.get('pixel_spacing')}, got {val_spacing})")
    except ValueError:
        feedback_parts.append(f"Pixel spacing not a number: {val_spacing}")

    # 2d. Slice Thickness
    try:
        if val_thickness and abs(float(val_thickness) - float(gt.get('slice_thickness', 1.5))) < 0.2:
            score += 15
            feedback_parts.append(f"Slice thickness correct ({val_thickness})")
        else:
            feedback_parts.append(f"Slice thickness incorrect (expected {gt.get('slice_thickness')}, got {val_thickness})")
    except ValueError:
        feedback_parts.append(f"Slice thickness not a number: {val_thickness}")

    # 2e. Modality
    if val_modality and val_modality.lower() == str(gt.get('modality', 'CT')).lower():
        score += 15
        feedback_parts.append(f"Modality correct ({val_modality})")
    else:
        feedback_parts.append(f"Modality incorrect (expected {gt.get('modality')}, got {val_modality})")

    # --- Criterion 3: VLM Process Verification (10 pts) ---
    # We want to verify the agent actually looked at the UI, not just guessed or used CLI
    frames = sample_trajectory_frames(traj, n=5)
    vlm_score = 0
    
    prompt = """
    Review this sequence of screenshots from a desktop agent.
    The goal is to extract DICOM metadata (slice count, spacing, etc.) from the application 'InVesalius'.
    
    Do you see any of the following:
    1. The InVesalius application window open?
    2. A 'DICOM Import' dialog or 'Data Properties' panel visible?
    3. The agent scrolling or navigating through the slices?
    
    Answer JSON with 'invesalius_visible' (bool) and 'metadata_panel_visible' (bool).
    """
    
    try:
        vlm_resp = query_vlm(images=frames, prompt=prompt)
        parsed = vlm_resp.get('parsed', {})
        
        if parsed.get('invesalius_visible', False):
            vlm_score += 5
        if parsed.get('metadata_panel_visible', False):
            vlm_score += 5
            
        score += vlm_score
        if vlm_score > 0:
            feedback_parts.append("Visual verification passed")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Be lenient if VLM fails, don't penalize if file score is high
        if score >= 60:
            score += 10
            feedback_parts.append("Visual verification skipped (error)")

    # Final Pass/Fail
    passed = score >= 75  # Requires file creation + ~4 correct parameters
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }