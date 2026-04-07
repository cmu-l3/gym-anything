#!/usr/bin/env python3
"""
Verifier for retime_double_speed_render task.

Goal: Retime animation to double speed (2x).
Success requires:
1. Output frames exist.
2. Output frame count is approximately 50% of the original frame count.
3. Files were created during the task.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_retime_double_speed(traj, env_info, task_info):
    """
    Verify that the animation was rendered at double speed (approx half frame count).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    min_size_kb = metadata.get('min_output_size_kb', 100)
    ratio_min = metadata.get('ratio_min', 0.4) # Allow some slack around 0.5
    ratio_max = metadata.get('ratio_max', 0.65)
    
    # Retrieve result file
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

    # Extract metrics
    original_count = result.get('original_frame_count', 0)
    output_count = result.get('output_frame_count', 0)
    new_files_count = result.get('new_files_count', 0)
    total_size_bytes = result.get('total_size_bytes', 0)
    
    score = 0
    feedback_parts = []
    
    # Safety check on original count
    if original_count <= 0:
        # Fallback if setup failed to detect count
        original_count = 13 # Reasonable default for dwanko_run
        feedback_parts.append("(Using default baseline for original frames)")

    # 1. Check if files exist (15 pts)
    if output_count > 0:
        score += 15
        feedback_parts.append(f"Output frames found: {output_count}")
    else:
        feedback_parts.append("No output frames found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Check reduction logic (Double speed = Half frames) (40 pts)
    # The count should be strictly less than original
    if output_count >= original_count:
        feedback_parts.append(f"Frame count NOT reduced (Original: {original_count}, Output: {output_count}). Did not speed up.")
    else:
        ratio = output_count / original_count
        if ratio_min <= ratio <= ratio_max:
            score += 40
            feedback_parts.append(f"Frame reduction correct ({ratio:.2f}x of original). Double speed achieved.")
        else:
            # Partial credit if reduced but not quite double speed
            score += 10
            feedback_parts.append(f"Frame count reduced but ratio off ({ratio:.2f}x). Expected ~0.5x.")

    # 3. Check Anti-Gaming (Files created during task) (25 pts)
    if new_files_count >= output_count and new_files_count > 0:
        score += 25
        feedback_parts.append("All files created during task session.")
    elif new_files_count > 0:
        score += 10
        feedback_parts.append(f"Some files older than task start ({new_files_count}/{output_count} new).")
    else:
        feedback_parts.append("Files are old/pre-existing.")
        score = 0 # Fail if no new work done

    # 4. Check File Size (Content Validity) (20 pts)
    total_size_kb = total_size_bytes / 1024
    if total_size_kb >= min_size_kb:
        score += 20
        feedback_parts.append(f"Output size substantial ({int(total_size_kb)}KB).")
    else:
        feedback_parts.append(f"Output file size too small ({int(total_size_kb)}KB).")

    # Pass logic: Must have reduced frames substantially and created new files
    passed = (score >= 60) and (output_count < original_count) and (new_files_count > 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }