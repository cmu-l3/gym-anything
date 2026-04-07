#!/usr/bin/env python3
"""
Verifier for invert_colors_negative_render task.

Scoring Criteria:
1. Frame Count >= 10: 20 pts
2. Output created during task (anti-gaming): 20 pts
3. Background is DARK (pixel analysis < 50 brightness): 35 pts (CRITICAL)
   - Verifies the 'Invert' effect was actually applied to the white background.
4. Valid Dimensions (>=100x100): 15 pts
5. File Size / Content Check: 10 pts

Pass Threshold: 55 points AND background must be dark (inversion confirmed).
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_invert_colors_negative_render(traj, env_info, task_info):
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    min_frame_count = metadata.get('min_frame_count', 10)
    max_bg_brightness = metadata.get('max_background_brightness', 50) # 0=Black, 255=White

    # Read Result
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
    
    # 1. Frame Count (20 pts)
    file_count = result.get('file_count', 0)
    if file_count >= min_frame_count:
        score += 20
        feedback_parts.append(f"Frame count OK ({file_count})")
    elif file_count > 0:
        score += 5
        feedback_parts.append(f"Partial frames ({file_count}/{min_frame_count})")
    else:
        feedback_parts.append("No output frames found")

    # 2. Anti-gaming / Timestamp (20 pts)
    new_files = result.get('new_files_count', 0)
    if new_files >= min_frame_count:
        score += 20
        feedback_parts.append("Files created during task")
    elif new_files > 0:
        score += 10
        feedback_parts.append(f"Some new files ({new_files})")
    else:
        feedback_parts.append("No new files created (timestamps old or files missing)")

    # 3. Background Inversion Check (35 pts) - CRITICAL
    # Original BG is white (approx 255). Inverted should be Black (approx 0).
    bg_brightness = float(result.get('bg_brightness', 255))
    has_content = result.get('has_content', False)
    
    inversion_passed = False
    if bg_brightness <= max_bg_brightness:
        score += 35
        inversion_passed = True
        feedback_parts.append(f"Effect Verified: Background is dark (Level: {bg_brightness:.1f})")
    elif bg_brightness > 200:
        feedback_parts.append(f"Effect FAILED: Background is white (Level: {bg_brightness:.1f}) - No inversion detected")
    else:
        # Gray area (maybe partial effect or different color)
        score += 10
        feedback_parts.append(f"Effect Unclear: Background is gray (Level: {bg_brightness:.1f})")

    # 4. Dimensions (15 pts)
    width = result.get('img_width', 0)
    height = result.get('img_height', 0)
    if width > 100 and height > 100:
        score += 15
        feedback_parts.append(f"Dimensions valid ({width}x{height})")
    else:
        feedback_parts.append("Invalid image dimensions")

    # 5. Content/Size (10 pts)
    # Ensure it's not just a black square (content check from python script)
    total_size = result.get('total_size_kb', 0)
    if has_content and total_size > 50:
        score += 10
        feedback_parts.append("Content detected in render")
    elif total_size > 0:
        score += 5
        feedback_parts.append("File exists but content check ambiguous")
    else:
        feedback_parts.append("File empty or missing")

    # Final logic
    # Must have reasonably passed frame count AND inversion check to pass
    passed = (score >= 55) and inversion_passed and (file_count >= 1)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }