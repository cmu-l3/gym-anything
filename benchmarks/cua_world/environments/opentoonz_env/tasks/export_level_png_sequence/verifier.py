#!/usr/bin/env python3
"""
Verifier for export_level_png_sequence task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_level_png_sequence(traj, env_info, task_info):
    """
    Verify that the agent exported the animation level as a PNG sequence.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Metrics
    file_count = result.get("file_count", 0)
    new_files_count = result.get("new_files_count", 0)
    analysis = result.get("first_file_analysis", {})
    
    has_alpha = analysis.get("has_alpha", False)
    has_content = analysis.get("has_content", False)
    mode = analysis.get("mode", "Unknown")

    metadata = task_info.get("metadata", {})
    min_frames = metadata.get("min_frame_count", 8)

    # 3. Scoring Logic
    score = 0
    feedback = []

    # Criterion 1: Files Exist (20 pts)
    if file_count > 0:
        score += 20
        feedback.append(f"Found {file_count} PNG files.")
    else:
        feedback.append("No PNG files found in output directory.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: Frame Count (20 pts)
    if file_count >= min_frames:
        score += 20
        feedback.append(f"Frame count sufficient (>= {min_frames}).")
    elif file_count >= 1:
        # Partial credit
        score += 10
        feedback.append(f"Frame count low ({file_count} < {min_frames}).")

    # Criterion 3: Alpha Channel / RGBA (25 pts)
    # This distinguishes 'Save Level' (usually RGBA) from 'Render Scene' (often RGB background)
    if has_alpha:
        score += 25
        feedback.append("Alpha channel present (RGBA mode).")
    else:
        feedback.append(f"No alpha channel detected (Mode: {mode}). Likely a scene render with background.")

    # Criterion 4: Content Validation (15 pts)
    # Ensures not just empty transparent frames
    if has_content:
        score += 15
        feedback.append("Image content detected (visible pixels).")
    else:
        feedback.append("Images appear to be blank or fully transparent.")

    # Criterion 5: Anti-Gaming / Freshness (20 pts)
    if new_files_count >= min_frames:
        score += 20
        feedback.append("All files created during task session.")
    elif new_files_count > 0:
        score += 10
        feedback.append(f"Only {new_files_count} files created during session.")
    else:
        feedback.append("Files are old (pre-existing) or not created during this session.")
        # If files aren't new, we shouldn't pass even if other criteria met
        score = min(score, 40)

    # 4. Final Result
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }