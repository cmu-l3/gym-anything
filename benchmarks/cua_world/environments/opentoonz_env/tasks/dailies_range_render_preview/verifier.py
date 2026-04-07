#!/usr/bin/env python3
"""
Verifier for dailies_range_render_preview task.

Critera:
1. Target frames (5-15) MUST exist.
2. Frames OUTSIDE target range (1-4, 16+) MUST NOT exist (efficiency check).
3. Resolution MUST be 960x540.
4. Files must be created during the task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dailies_range_render_preview(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    expected_width = metadata.get('expected_width', 960)
    expected_height = metadata.get('expected_height', 540)
    target_start = metadata.get('target_start_frame', 5)
    target_end = metadata.get('target_end_frame', 15)
    
    # Calculate total expected frames
    expected_count = target_end - target_start + 1

    # 2. Retrieve Result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
            analysis = data.get('analysis', {})
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Analyze Data
    frames_found = analysis.get('frames_indices', [])
    extra_frames = analysis.get('extra_frames_indices', [])
    missing_frames = analysis.get('missing_frames_indices', [])
    resolution = analysis.get('resolution', [0, 0])
    is_fresh = analysis.get('files_fresh', False)
    valid_format = analysis.get('valid_image_format', False)
    
    score = 0
    feedback = []

    # Criterion 1: Target Frames Exist (25 pts)
    # Scale based on how many of the required frames are present
    if not frames_found:
        feedback.append(f"No frames in target range {target_start}-{target_end} found.")
    else:
        found_count = len(frames_found)
        fraction = found_count / expected_count
        pts = int(25 * fraction)
        score += pts
        if len(missing_frames) == 0:
            feedback.append(f"All target frames ({target_start}-{target_end}) found.")
        else:
            feedback.append(f"Partial target frames found ({found_count}/{expected_count}). Missing: {missing_frames}.")

    # Criterion 2: Outside Frames Absent (25 pts) - "Efficiency Check"
    # If extras exist, penalty.
    if len(extra_frames) == 0 and len(frames_found) > 0:
        score += 25
        feedback.append("Correctly rendered ONLY the requested range.")
    elif len(extra_frames) > 0:
        # Penalty: If they rendered > 5 extra frames, 0 points for this section.
        # If small slip up (1-2 frames), partial credit.
        if len(extra_frames) <= 2:
            score += 15
            feedback.append(f"Slight range error: {len(extra_frames)} extra frames found.")
        else:
            feedback.append(f"Inefficient render: {len(extra_frames)} extra frames found outside range (e.g., {extra_frames[:3]}...).")
    
    # Criterion 3: Resolution Check (30 pts)
    # Allow small tolerance? Usually exact match expected for resolution settings.
    # OpenToonz sometimes varies by 1px depending on odd/even inputs, but 960x540 is standard even numbers.
    width, height = resolution
    if width == expected_width and height == expected_height:
        score += 30
        feedback.append(f"Resolution verified: {width}x{height}.")
    elif width > 0:
        feedback.append(f"Incorrect resolution: {width}x{height} (Expected {expected_width}x{expected_height}).")
    else:
        feedback.append("Could not determine resolution (no valid images).")

    # Criterion 4: Freshness (10 pts)
    if is_fresh and len(frames_found) > 0:
        score += 10
        feedback.append("Files verified as newly created.")
    elif len(frames_found) > 0:
        feedback.append("Files appear to be old/pre-existing.")
    
    # Criterion 5: Validity (10 pts)
    if valid_format and analysis.get('total_size_bytes', 0) > 1024:
        score += 10
        feedback.append("Output files are valid images.")
    
    # Final Pass/Fail Logic
    # Must have correct range AND resolution to pass comfortably.
    passed = score >= 60 and len(frames_found) >= (expected_count - 1) and width == expected_width
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }