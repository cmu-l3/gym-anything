#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rotoscope_movement_trace(traj, env_info, task_info):
    """
    Verify the rotoscope task.
    
    Criteria:
    1. Output Files Exist (20 pts)
    2. New Level Created (Evidence of drawing tool usage) (20 pts)
    3. Reference Visible (Did not overwrite bg with white) (20 pts)
    4. Trace Detected (Output differs from raw reference) (20 pts)
    5. Animation Detected (Frames change over time) (20 pts)
    """
    
    # 1. Retrieve Result JSON from Environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Score Calculation
    score = 0
    feedback = []
    
    # Criterion 1: Output Count
    output_count = result.get("output_count", 0)
    if output_count >= 20: # Allow slight buffer for 24 frames
        score += 20
        feedback.append("Rendered sequence found.")
    elif output_count > 0:
        score += 10
        feedback.append(f"Partial render found ({output_count} frames).")
    else:
        feedback.append("No output files found.")

    # Criterion 2: New Level (Drawing)
    if result.get("new_level_found", False):
        score += 20
        feedback.append("New drawing level created.")
    else:
        feedback.append("No new drawing level detected (did you save the scene?).")

    # Criterion 3: Reference Visibility
    if result.get("ref_visible", False):
        score += 20
        feedback.append("Reference footage is visible in output.")
    else:
        feedback.append("Reference footage not visible (background might be opaque white).")

    # Criterion 4: Trace Detection
    if result.get("trace_detected", False):
        score += 20
        feedback.append("Tracing strokes detected on top of reference.")
    else:
        feedback.append("No tracing strokes detected (output matches reference exactly).")

    # Criterion 5: Animation
    if result.get("animation_detected", False):
        score += 20
        feedback.append("Animation movement detected.")
    else:
        feedback.append("Output appears static (no movement).")

    # VLM Trajectory Verification (Optional bonus/confirmation)
    # Could add VLM check here to confirm "red lines" specifically if needed, 
    # but the image comparison in export_result is robust enough for "trace detected".

    passed = score >= 60 and output_count > 0
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }