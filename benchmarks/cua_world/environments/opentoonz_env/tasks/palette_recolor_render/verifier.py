#!/usr/bin/env python3
"""
Verifier for palette_recolor_render task.

Verifies:
1. Output files exist in the correct directory.
2. Sufficient number of frames rendered (>= 20).
3. Frames contain the specific requested color (Orange #FF6600).
4. Frames were created during the task session.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_palette_recolor_render(traj, env_info, task_info):
    """
    Verify that the OpenToonz scene was recolored and rendered correctly.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    min_frames = metadata.get('min_frame_count', 20)
    # Note: The pixel count threshold in metadata might need adjustment based on the thumbnailing in export_result.sh
    # In export_result, we thumbnail to 400x400. 
    # A character outline in a 400x400 thumbnail might only be 100-500 pixels total depending on thickness.
    # Let's be lenient: if we see *any* significant cluster of orange pixels, they likely succeeded.
    min_orange_pixels = 20 

    # 2. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "No result file found. Did the export script run?"}
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "Result file corrupted."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Scoring Logic
    score = 0
    feedback = []

    # Criterion 1: Output exists (10 pts)
    if result.get('output_exists'):
        score += 10
        feedback.append("Output directory exists.")
    else:
        feedback.append("Output directory not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: File count (25 pts)
    file_count = result.get('file_count', 0)
    if file_count >= min_frames:
        score += 25
        feedback.append(f"Frame count valid ({file_count} >= {min_frames}).")
    elif file_count > 0:
        # Partial credit
        score += 10
        feedback.append(f"Insufficient frames ({file_count} < {min_frames}).")
    else:
        feedback.append("No rendered frames found.")

    # Criterion 3: Created during task (Anti-gaming) (25 pts)
    new_files = result.get('files_created_during_task', 0)
    if new_files >= min_frames:
        score += 25
        feedback.append("Files created during task session.")
    elif new_files > 0:
        score += 10
        feedback.append("Some files from previous sessions found.")
    else:
        feedback.append("No new files created.")

    # Criterion 4: Color verification (40 pts)
    # This is the core check for "recoloring"
    avg_orange = result.get('avg_orange_pixels', 0)
    max_orange = result.get('max_orange_pixels', 0)
    
    if avg_orange >= min_orange_pixels:
        score += 40
        feedback.append(f"Orange recolor verified (avg {avg_orange:.1f} target pixels/frame).")
    elif max_orange >= min_orange_pixels:
        # Maybe inconsistent rendering or only some frames visible
        score += 20
        feedback.append(f"Inconsistent recolor detected (max {max_orange} target pixels).")
    else:
        feedback.append("Recolor NOT detected. No significant #FF6600 pixels found.")

    # Pass Threshold
    passed = score >= 80  # Requires basically everything to be right
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }