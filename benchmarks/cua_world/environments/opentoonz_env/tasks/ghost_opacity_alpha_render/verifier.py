#!/usr/bin/env python3
"""
Verifier for ghost_opacity_alpha_render task.

Verifies:
1. Output files exist and are created during task.
2. Output format is PNG with Alpha Channel (RGBA).
3. Content has reduced opacity (median alpha check).
4. Content is not fully opaque (default render) or fully transparent (blank).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ghost_opacity_alpha_render(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_frame_count = metadata.get('min_frame_count', 24)
    target_opacity_min = metadata.get('target_opacity_min', 64)   # ~25%
    target_opacity_max = metadata.get('target_opacity_max', 200)  # ~78% (generous upper bound)
    min_semitransparent_ratio = metadata.get('min_semitransparent_ratio', 0.1)

    # Copy result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    file_count = result.get('file_count', 0)
    files_newer = result.get('files_newer_than_start', False)
    analysis = result.get('image_analysis', {})
    
    is_rgba = analysis.get('is_rgba', False)
    median_alpha = analysis.get('median_alpha', 255)
    semi_ratio = analysis.get('semi_transparent_ratio', 0.0)
    opaque_ratio = analysis.get('fully_opaque_ratio', 1.0)
    valid_png = analysis.get('valid_png', False)

    # 1. File Count (20 pts)
    if file_count >= min_frame_count:
        score += 20
        feedback_parts.append(f"Frame count OK ({file_count})")
    elif file_count > 0:
        score += 10
        feedback_parts.append(f"Frame count low ({file_count}/{min_frame_count})")
    else:
        feedback_parts.append("No output files found")

    # 2. Anti-gaming / Timestamp (15 pts)
    if files_newer:
        score += 15
        feedback_parts.append("Files created during task")
    else:
        feedback_parts.append("Files not created during task window")

    # 3. Alpha Channel Presence (20 pts)
    if is_rgba:
        score += 20
        feedback_parts.append("Alpha channel present (RGBA)")
    elif valid_png:
        feedback_parts.append("Rendered RGB (missing alpha channel)")
    else:
        feedback_parts.append("Invalid or missing image data")

    # 4. Opacity Verification (45 pts total)
    # This is the core check. Default render is opaque (alpha 255).
    # Correct task requires ~50% opacity (alpha ~128).
    
    if not is_rgba or not valid_png:
        score += 0 # Cannot verify opacity without alpha channel
    else:
        # Check for empty frames
        if median_alpha == 0 and semi_ratio == 0:
            feedback_parts.append("Frames appear empty/blank")
        # Check for default opaque render
        elif median_alpha >= 250 and opaque_ratio > 0.9:
            feedback_parts.append("Frames are fully opaque (opacity not reduced)")
        # Check for correct semi-transparency
        elif target_opacity_min <= median_alpha <= target_opacity_max:
            score += 30
            feedback_parts.append(f"Opacity correct (Median Alpha: {median_alpha:.1f})")
            
            # Bonus for significant semi-transparent content (confirms it's not just 1 pixel)
            if semi_ratio > min_semitransparent_ratio:
                score += 15
                feedback_parts.append("Content properly composited")
            else:
                feedback_parts.append("Content sparse or inconsistent")
        else:
            feedback_parts.append(f"Opacity out of range (Median Alpha: {median_alpha:.1f})")

    passed = score >= 60 and is_rgba
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }