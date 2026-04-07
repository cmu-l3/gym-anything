#!/usr/bin/env python3
"""
Verifier for pip_corner_composition_render task.

Verifies that the agent:
1. Rendered a frame sequence (>= 24 frames)
2. Created files during the task (anti-gaming)
3. Spatially positioned the content in the BOTTOM-RIGHT corner (PiP effect)
   - Checks pixel density in quadrants
   - Requires Bottom-Right density >> Top-Left density
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pip_corner_composition(traj, env_info, task_info):
    """
    Verify the PiP corner composition task.
    """
    # 1. Setup Interface
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 2. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Extract Metrics
    file_count = result.get('file_count', 0)
    new_files_count = result.get('new_files_count', 0)
    total_size = result.get('total_size_bytes', 0)
    quadrant_data = result.get('quadrant_analysis', {})
    
    tl_density = float(quadrant_data.get('top_left_density', 0))
    br_density = float(quadrant_data.get('bottom_right_density', 0))
    
    # 4. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criterion 1: Render Quantity (15 pts)
    # Expecting 24 frames
    if new_files_count >= 24:
        score += 15
        feedback_parts.append(f"Rendered {new_files_count} frames (Pass)")
    elif new_files_count > 0:
        partial = int(15 * (new_files_count / 24))
        score += partial
        feedback_parts.append(f"Rendered only {new_files_count}/24 frames (Partial)")
    else:
        feedback_parts.append("No new frames rendered")

    # Criterion 2: Temporal Validity (15 pts)
    # Check if files were actually created during task (handled by new_files_count logic above effectively,
    # but we give explicit points for verifying timestamps to emphasize anti-gaming)
    if new_files_count == file_count and new_files_count > 0:
        score += 15
        feedback_parts.append("Files created during task session (Pass)")
    elif new_files_count > 0:
        score += 10
        feedback_parts.append("Some files predated task (Warning)")
    
    # Criterion 3: Top-Left Empty (25 pts)
    # TL density should be low (empty background)
    # Threshold: < 10% pixels occupied
    if tl_density < 0.10:
        score += 25
        feedback_parts.append(f"Top-Left corner matches empty spec (Density: {tl_density:.2%})")
    else:
        feedback_parts.append(f"Top-Left corner not empty (Density: {tl_density:.2%}) - Did you move the animation?")

    # Criterion 4: Bottom-Right Content (25 pts)
    # BR density should be high enough to show content
    # Threshold: > 3% pixels occupied (animation might be sparse, but must be present)
    if br_density > 0.03:
        score += 25
        feedback_parts.append(f"Bottom-Right corner contains content (Density: {br_density:.2%})")
    else:
        feedback_parts.append(f"Bottom-Right corner appears empty (Density: {br_density:.2%})")

    # Criterion 5: Spatial Asymmetry (10 pts)
    # Prove it was moved: BR should be significantly denser than TL
    # Avoids case where user just scaled it but left it centered (TL and BR would be roughly equal or both empty)
    # Or full screen (TL and BR both full)
    
    # Case A: Both empty
    if tl_density < 0.01 and br_density < 0.01:
        ratio_score = 0
        feedback_parts.append("Frame appears blank")
    # Case B: Valid content
    elif br_density > (tl_density * 3) or (tl_density < 0.01 and br_density > 0.03):
        score += 10
        feedback_parts.append("Correct spatial positioning detected")
    else:
        feedback_parts.append("Content not correctly positioned in corner")

    # Criterion 6: Total Output Size (10 pts)
    # Rough check for non-blank files
    if total_size > 200 * 1024: # 200KB
        score += 10
        feedback_parts.append("Output file size reasonable")
    elif total_size > 0:
        score += 5
        feedback_parts.append("Output file size low")

    # 5. Final Result
    # Pass threshold: 60 points
    # Critical failure check: If BR density is 0, they definitely failed the goal
    passed = (score >= 60) and (br_density > 0.01)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }