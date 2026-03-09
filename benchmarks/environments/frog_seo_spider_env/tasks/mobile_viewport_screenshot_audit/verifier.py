#!/usr/bin/env python3
"""
Verifier for Mobile Viewport Screenshot Audit task.

Scoring (100 points total):
1. Export folder 'mobile_screenshots' exists (20 pts)
2. At least 5 images created after task start (30 pts)
3. Image width corresponds to mobile viewport (~375px) (30 pts)
   - Checks average width of exported images
   - Tolerance +/- 25px
4. Images are valid format (20 pts)

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mobile_viewport_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    expected_width = metadata.get('expected_width', 375)
    width_tolerance = metadata.get('width_tolerance', 25)
    min_count = metadata.get('min_image_count', 5)

    score = 0
    feedback_parts = []

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

    # Criterion 1: Folder Exists (20 pts)
    if result.get('folder_exists', False):
        score += 20
        feedback_parts.append("Export folder found (20/20)")
    else:
        feedback_parts.append("Export folder 'mobile_screenshots' not found (0/20)")

    # Criterion 2: Image Count (30 pts)
    # Only count images created during task
    valid_count = result.get('valid_images_count', 0)
    if valid_count >= min_count:
        score += 30
        feedback_parts.append(f"Found {valid_count} new images (30/30)")
    elif valid_count > 0:
        partial = int(30 * (valid_count / min_count))
        score += partial
        feedback_parts.append(f"Found {valid_count}/{min_count} images ({partial}/30)")
    else:
        feedback_parts.append("No valid images found created during task (0/30)")

    # Criterion 3: Dimensions Check (30 pts)
    avg_width = result.get('average_width', 0)
    width_diff = abs(avg_width - expected_width)
    
    if valid_count > 0:
        if width_diff <= width_tolerance:
            score += 30
            feedback_parts.append(f"Average width {avg_width:.1f}px matches mobile target {expected_width}px (30/30)")
        elif width_diff <= 100:
            # Partial credit if they changed size but maybe wrong device
            score += 15
            feedback_parts.append(f"Average width {avg_width:.1f}px close to target (15/30)")
        elif avg_width > 1000:
            # Desktop width - no points for this section
            feedback_parts.append(f"Average width {avg_width:.1f}px indicates DESKTOP viewport, not mobile (0/30)")
        else:
            feedback_parts.append(f"Average width {avg_width:.1f}px incorrect (target {expected_width}px) (0/30)")
    else:
        feedback_parts.append("Cannot verify dimensions (no images) (0/30)")

    # Criterion 4: Valid Format (20 pts)
    # If the export script successfully parsed headers, they are valid formats
    if valid_count > 0:
        score += 20
        feedback_parts.append("Images are valid formats (20/20)")
    else:
        feedback_parts.append("No valid images to check format (0/20)")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }