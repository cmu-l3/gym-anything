#!/usr/bin/env python3
"""Verifier for render_animation task.

Checks that the user successfully rendered an animation from OpenToonz.
"""

import json
import tempfile
import os


def verify_render_animation(traj, env_info, task_info):
    """Verify that animation was rendered successfully.

    Args:
        traj: Trajectory data (not used)
        env_info: Environment information including copy_from_env function
        task_info: Task metadata including expected values

    Returns:
        dict: {"passed": bool, "score": int, "feedback": str}
    """

    # Get copy function from framework
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_output = metadata.get('expected_output', '/home/ga/OpenToonz/outputs/rendered_animation.mp4')
    min_file_size_kb = metadata.get('min_file_size_kb', 10)

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Evaluate results
    score = 0
    feedback_parts = []

    # Criterion 1: Output file found (30 points)
    output_found = result.get('output_found', False)
    if output_found:
        score += 30
        output_path = result.get('output_path', 'unknown')
        feedback_parts.append(f"Output file found: {os.path.basename(output_path)}")
    else:
        feedback_parts.append("No output video file found")

    # Criterion 2: File size check (30 points)
    output_size_kb = result.get('output_size_kb', 0)
    if output_size_kb >= min_file_size_kb:
        score += 30
        feedback_parts.append(f"File size OK: {output_size_kb} KB")
    elif output_size_kb > 0:
        score += 15  # Partial credit for small file
        feedback_parts.append(f"File too small: {output_size_kb} KB (expected >= {min_file_size_kb} KB)")
    else:
        feedback_parts.append(f"File size: 0 KB")

    # Criterion 3: Render success indicator (20 points)
    render_success = result.get('render_success', False)
    if render_success:
        score += 20
        feedback_parts.append("Render marked as successful")
    else:
        feedback_parts.append("Render not fully successful")

    # Criterion 4: New output created (20 points)
    initial_count = result.get('initial_output_count', 0)
    current_count = result.get('current_output_count', 0)
    if current_count > initial_count:
        score += 20
        feedback_parts.append(f"New output created ({initial_count} -> {current_count} files)")
    else:
        feedback_parts.append("No new output files created")

    # Determine pass/fail
    # Pass if we have output and it's a reasonable size
    passed = output_found and output_size_kb >= min_file_size_kb

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
