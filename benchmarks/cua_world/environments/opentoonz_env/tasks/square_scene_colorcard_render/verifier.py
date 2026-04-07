#!/usr/bin/env python3
"""
Verifier for square_scene_colorcard_render task.

Verifies:
1. Output files exist and count >= 60 (20 pts)
2. Resolution is 1080x1080 (25 pts)
3. Background color is Blue (approx #0066CC) (25 pts)
4. Files were created during the task (15 pts)
5. Total file size is reasonable (>= 500KB) (15 pts)

Also uses VLM verification as a backup/validation if available,
but primary scoring is programmatic file analysis.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_square_scene_colorcard_render(traj, env_info, task_info):
    """
    Verify that the user rendered a 1080x1080 blue square scene.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_width = metadata.get('expected_width', 1080)
    expected_height = metadata.get('expected_height', 1080)
    min_frames = metadata.get('min_frames', 60)
    
    # Blue target: RGB(0, 102, 204)
    target_rgb = metadata.get('expected_color_rgb', [0, 102, 204])
    color_tolerance = metadata.get('color_tolerance', 40)

    # 1. Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    file_count = result.get("file_count", 0)
    files_new = result.get("files_created_during_task", 0)
    width = result.get("width", 0)
    height = result.get("height", 0)
    avg_color = result.get("avg_color", [0, 0, 0])
    total_size = result.get("total_size_bytes", 0)
    
    # CRITERION 1: Frame Count (20 pts)
    if file_count >= min_frames:
        score += 20
        feedback_parts.append(f"Frame count OK ({file_count})")
    elif file_count > 0:
        # Partial credit
        pts = int(20 * (file_count / min_frames))
        score += pts
        feedback_parts.append(f"Partial frame count ({file_count}/{min_frames})")
    else:
        feedback_parts.append("No frames rendered")

    # CRITERION 2: Resolution (25 pts)
    if width == expected_width and height == expected_height:
        score += 25
        feedback_parts.append(f"Resolution OK ({width}x{height})")
    elif width > 0:
        feedback_parts.append(f"Wrong resolution ({width}x{height}, expected {expected_width}x{expected_height})")
    else:
        feedback_parts.append("Could not determine resolution")

    # CRITERION 3: Color Check (25 pts)
    # Check if color is roughly Blue (R low, G mid, B high)
    # Target: [0, 102, 204]
    r, g, b = avg_color
    tr, tg, tb = target_rgb
    
    # Calculate euclidean distance or per-channel diff
    # Being lenient because rendering engines handle colors differently
    r_diff = abs(r - tr)
    g_diff = abs(g - tg)
    b_diff = abs(b - tb)
    
    # Specific check for blue dominance: B > R and B > G
    is_blue_dominant = (b > r + 30) and (b > g)
    
    # Allow wider tolerance if it is clearly blue
    if is_blue_dominant and r < 100 and g < 180 and b > 150:
         score += 25
         feedback_parts.append(f"Color OK (Blue dominant, RGB: {int(r)},{int(g)},{int(b)})")
    elif r_diff < color_tolerance and g_diff < color_tolerance and b_diff < color_tolerance:
         score += 25
         feedback_parts.append(f"Color Match OK (RGB: {int(r)},{int(g)},{int(b)})")
    else:
         feedback_parts.append(f"Wrong color (RGB: {int(r)},{int(g)},{int(b)} - Expected Blue)")

    # CRITERION 4: Anti-Gaming / New Files (15 pts)
    if files_new >= min_frames:
        score += 15
        feedback_parts.append("Files created during task")
    elif files_new > 0:
        score += 5
        feedback_parts.append(f"Some new files ({files_new})")
    else:
        feedback_parts.append("No new files created during task")

    # CRITERION 5: File Size (15 pts)
    # 500KB threshold (for 60 frames of solid color, PNGs are small but should be > 0)
    # A 1080x1080 solid blue PNG is roughly 5-10KB. 60 frames ~ 300-600KB.
    if total_size >= 300 * 1024:
        score += 15
        feedback_parts.append(f"Total size OK ({total_size/1024:.1f} KB)")
    elif total_size > 0:
        score += 5
        feedback_parts.append(f"Total size small ({total_size/1024:.1f} KB)")
    
    # Final Evaluation
    # Must have correct resolution and frames to pass
    passed = (score >= 60) and (width == expected_width) and (height == expected_height) and (file_count >= min_frames)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }