#!/usr/bin/env python3
"""
Verifier for audit_scan_resolution task.

Verifies that the agent correctly identified the Voxel Size and Dimensions
of the loaded scan by checking the text file created.
"""

import json
import re
import tempfile
import os
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Ground truth values (should match the loaded dataset)
# In a production setup, these might be read dynamically from the DICOM files
# But here we align with the metadata in task.json
DEFAULT_GROUND_TRUTH = {
    "voxel_size_mm": 0.3,
    "dimensions": [512, 512, 400],
    "voxel_tolerance": 0.01
}

def parse_agent_output(content: str):
    """
    Parses the text file content to extract voxel size and dimensions.
    Expected format:
       Voxel Size: 0.3 x 0.3 x 0.3 mm
       Dimensions: 512 x 512 x 400
    """
    data = {
        "voxel_size": None,
        "dimensions": None
    }
    
    # Extract Voxel Size (look for sequences of numbers like 0.3)
    voxel_match = re.search(r"Voxel.*?:.*?([\d\.]+).*?([\d\.]+).*?([\d\.]+)", content, re.IGNORECASE)
    if voxel_match:
        try:
            # We assume isotropic or we take the first value as the representative size if single value given
            # Or parse all 3
            v1, v2, v3 = map(float, voxel_match.groups())
            data["voxel_size"] = [v1, v2, v3]
        except ValueError:
            pass
            
    # Extract Dimensions (look for integers)
    dim_match = re.search(r"Dimensions.*?:.*?(\d+).*?(\d+).*?(\d+)", content, re.IGNORECASE)
    if dim_match:
        try:
            d1, d2, d3 = map(int, dim_match.groups())
            data["dimensions"] = [d1, d2, d3]
        except ValueError:
            pass
            
    return data

def verify_audit_scan_resolution(traj, env_info, task_info):
    """
    Verify the audit report.
    """
    # 1. Setup access to container files
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', DEFAULT_GROUND_TRUTH)
    
    # 2. Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # 3. Analyze Criteria
    score = 0
    feedback_parts = []
    
    # Criterion 1: File Creation (20 pts)
    if result.get("file_exists") and result.get("file_created_during_task"):
        score += 20
        feedback_parts.append("Audit file created successfully.")
    elif result.get("file_exists"):
        score += 10
        feedback_parts.append("Audit file exists but timestamp is old (anti-gaming warning).")
    else:
        return {"passed": False, "score": 0, "feedback": "Audit file not found at expected location."}

    # Criterion 2: Content Parsing & Accuracy (80 pts)
    content = result.get("file_content", "")
    parsed = parse_agent_output(content)
    
    # Check Voxel Size (40 pts)
    gt_voxel = ground_truth["voxel_size_mm"]
    tol = ground_truth["voxel_tolerance"]
    
    if parsed["voxel_size"]:
        # Check if any of the parsed dimensions match the expected voxel size
        # We allow format "0.3 x 0.3 x 0.3" or just "0.3"
        valid_voxel = all(abs(v - gt_voxel) <= tol for v in parsed["voxel_size"])
        if valid_voxel:
            score += 40
            feedback_parts.append(f"Voxel size correct ({parsed['voxel_size']}).")
        else:
            feedback_parts.append(f"Voxel size incorrect. Expected ~{gt_voxel}, got {parsed['voxel_size']}.")
    else:
        feedback_parts.append("Could not parse Voxel Size from file.")

    # Check Dimensions (40 pts)
    gt_dims = ground_truth["dimensions"]
    
    if parsed["dimensions"]:
        # Order might differ (X,Y,Z vs Z,Y,X), so we sort to compare set of dimensions
        if sorted(parsed["dimensions"]) == sorted(gt_dims):
            score += 40
            feedback_parts.append(f"Volume dimensions correct ({parsed['dimensions']}).")
        else:
            feedback_parts.append(f"Volume dimensions incorrect. Expected {gt_dims}, got {parsed['dimensions']}.")
    else:
        feedback_parts.append("Could not parse Volume Dimensions from file.")

    # 4. Final Verification
    passed = score >= 80  # Requires file + both values correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }