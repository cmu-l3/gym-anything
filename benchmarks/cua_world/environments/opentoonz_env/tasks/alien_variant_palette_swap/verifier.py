#!/usr/bin/env python3
"""
Verifier for the Alien Variant Palette Swap task.
Verifies that:
1. Output frames exist and were created during the task.
2. The character's skin color is Teal (palette swap success).
3. The outlines are still Black (lines preserved, not a global filter).
4. The background is not Teal (not a global tint).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_alien_variant_palette_swap(traj, env_info, task_info):
    """
    Verifies the palette swap task using image analysis data computed in the container.
    """
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # Copy the result JSON from the container
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    # 2. Extract Metrics
    file_count = result.get('file_count', 0)
    analysis = result.get('image_analysis', {})
    
    # 3. Score Calculation
    score = 0
    feedback_parts = []
    
    # Criterion 1: Files created (20 pts)
    min_frames = task_info.get('metadata', {}).get('min_frame_count', 10)
    if file_count >= min_frames:
        score += 20
        feedback_parts.append(f"Rendered {file_count} frames (Target: {min_frames})")
    elif file_count > 0:
        score += 10
        feedback_parts.append(f"Rendered {file_count} frames (Target: {min_frames}) - Partial Credit")
    else:
        feedback_parts.append("No output frames rendered")
        return {"passed": False, "score": 0, "feedback": "No output frames found. Did you render to the correct directory?"}

    # Criterion 2: Teal Color Presence (40 pts)
    # A successful palette swap should result in a significant amount of the target color
    teal_ratio = analysis.get('teal_ratio', 0)
    # Threshold: Assuming character takes up at least 5% of screen and skin is half of that
    if teal_ratio > 0.01: 
        score += 40
        feedback_parts.append("Teal color detected on character body")
    else:
        feedback_parts.append("Target Teal color (0, 255, 255) not found in output")

    # Criterion 3: Line Art Preservation (20 pts)
    # Black lines should still exist. If they are gone, the user might have tinted the whole image.
    black_ratio = analysis.get('black_ratio', 0)
    if black_ratio > 0.005:
        score += 20
        feedback_parts.append("Black outlines preserved")
    else:
        feedback_parts.append("Black outlines missing or tinted")

    # Criterion 4: Background/Global Tint Check (20 pts)
    # If the corner is Teal, they likely put a giant colored rectangle over everything or used a global FX
    corner_is_teal = analysis.get('corner_is_teal', False)
    if not corner_is_teal:
        score += 20
        feedback_parts.append("Background remains clean (not globally tinted)")
    else:
        feedback_parts.append("Background appears tinted Teal (incorrect method used)")

    # 4. Final Verdict
    # Passing requires frames exist + Teal is present + Background is NOT Teal
    key_requirements_met = (file_count > 0) and (teal_ratio > 0.01) and (not corner_is_teal)
    passed = (score >= 70) and key_requirements_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }