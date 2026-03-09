#!/usr/bin/env python3
"""
Verifier for MRI Stack Formatting task.

Task requirements:
1. Open T1 Head (16-bit, 256x256, 129 slices)
2. Convert to 8-bit
3. Scale to 75% (192x192)
4. Subsample Z to every 3rd slice (~43 slices)
5. Save to specific path

Scoring (100 pts):
- File existence & timestamp (Anti-gaming): 20 pts
- 8-bit conversion: 20 pts
- Spatial scaling (192x192 ±5): 20 pts
- Z-subsampling (43 ±3 slices): 30 pts
- Content validity (VLM/Basic checks): 10 pts
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mri_stack_formatting(traj, env_info, task_info):
    """
    Verify the MRI stack formatting task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Expected values
    orig_w = metadata.get('original_width', 256)
    orig_h = metadata.get('original_height', 256)
    orig_d = metadata.get('original_depth', 129)
    scale = metadata.get('target_scale', 0.75)
    step = metadata.get('target_step', 3)
    
    expected_w = int(orig_w * scale)
    expected_h = int(orig_h * scale)
    expected_d = int(orig_d / step) # Approx 43
    
    tol_dim = metadata.get('tolerance_dim', 5)
    tol_depth = metadata.get('tolerance_depth', 3)

    # Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/mri_stack_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. File Existence & Timestamp (20 pts)
    file_exists = result.get("file_exists", False)
    task_start = result.get("task_start_time", 0)
    file_mtime = result.get("file_mtime", 0)
    
    if file_exists:
        if file_mtime > task_start:
            score += 20
            feedback_parts.append("Output file created")
        else:
            feedback_parts.append("FAIL: File exists but is old (pre-dates task)")
            return {"passed": False, "score": 0, "feedback": "Anti-gaming: File not created during task"}
    else:
        feedback_parts.append("FAIL: Output file not found")
        return {"passed": False, "score": 0, "feedback": "Output file not found"}

    # 2. 8-bit Conversion (20 pts)
    is_8bit = result.get("is_8bit", False)
    dtype = result.get("dtype", "unknown")
    mode = result.get("mode", "unknown")
    
    if is_8bit:
        score += 20
        feedback_parts.append("8-bit conversion successful")
    else:
        feedback_parts.append(f"FAIL: Image is not 8-bit (Mode: {mode}, Dtype: {dtype})")

    # 3. Spatial Scaling (20 pts)
    width = result.get("width", 0)
    height = result.get("height", 0)
    
    # Calculate range
    w_min, w_max = expected_w - tol_dim, expected_w + tol_dim
    h_min, h_max = expected_h - tol_dim, expected_h + tol_dim
    
    if (w_min <= width <= w_max) and (h_min <= height <= h_max):
        score += 20
        feedback_parts.append(f"Dimensions correct ({width}x{height})")
    else:
        feedback_parts.append(f"FAIL: Dimensions incorrect. Expected ~{expected_w}x{expected_h}, got {width}x{height}")

    # 4. Z-Subsampling (30 pts)
    n_slices = result.get("n_slices", 0)
    d_min, d_max = expected_d - tol_depth, expected_d + tol_depth
    
    if d_min <= n_slices <= d_max:
        score += 30
        feedback_parts.append(f"Slice count correct ({n_slices})")
    elif n_slices == orig_d:
        feedback_parts.append(f"FAIL: Slice count unchanged ({n_slices}). Did not subsample.")
    else:
        feedback_parts.append(f"FAIL: Slice count incorrect. Expected ~{expected_d}, got {n_slices}")

    # 5. Content Validity / VLM (10 pts)
    # We verify that they actually did the work using VLM on trajectory
    # This prevents just generating a random file with python
    
    # Note: We rely on the output file properties primarily, but VLM ensures UI interaction
    # If file properties are perfect, we give 10 pts for "content validity" implicit in the properties
    # unless VLM flag is enabled in future. For now, checking file size > 1KB is a basic sanity check.
    
    file_size = result.get("file_size", 0)
    if file_size > 1024:
        score += 10
    else:
        feedback_parts.append("FAIL: File too small/empty")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }