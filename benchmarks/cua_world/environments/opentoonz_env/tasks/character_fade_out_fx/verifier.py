#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_character_fade_out_fx(traj, env_info, task_info):
    """
    Verifies that the agent animated a fade-out effect.
    
    Criteria:
    1. Output files exist and were created during the task.
    2. Frame 1 is opaque (visible).
    3. Frame 20 is transparent (invisible).
    4. Intermediate frames show a decreasing alpha trend.
    """
    
    # 1. Retrieve Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Evaluate
    score = 0
    feedback = []
    
    # Basic Checks
    file_count = data.get("file_count", 0)
    valid_time = data.get("files_valid_time", False)
    frame_data = data.get("frame_data", {})

    if file_count < 20:
        return {"passed": False, "score": 0, "feedback": f"Found only {file_count} frames. Expected at least 20."}
    
    score += 10 # Files exist
    feedback.append(f"Found {file_count} frames.")

    if valid_time:
        score += 10 # Anti-gaming check passed
        feedback.append("Files created during task session.")
    else:
        feedback.append("Warning: Files have old timestamps (pre-existing?).")

    # Alpha Analysis
    # We use center_max_alpha to detect if the character is there.
    # The character might not fill the whole screen, so mean_alpha might be low even if opaque.
    # max_alpha is good, but stray pixels might affect it. center_max is a good heuristic for dwanko.
    
    f1 = frame_data.get("1", {})
    f5 = frame_data.get("5", {})
    f10 = frame_data.get("10", {})
    f15 = frame_data.get("15", {})
    f20 = frame_data.get("20", {})

    # Check Start (Opaque)
    # Threshold: Expecting near 255. Let's say > 200.
    start_val = f1.get("center_max_alpha", 0)
    if start_val > 200:
        score += 25
        feedback.append("Frame 1 is opaque (Character visible).")
    elif start_val > 50:
        score += 10
        feedback.append(f"Frame 1 is partially visible ({start_val}), expected fully opaque.")
    else:
        feedback.append(f"Frame 1 is invisible ({start_val}).")

    # Check End (Transparent)
    # Threshold: Expecting near 0. Let's say < 10.
    end_val = f20.get("center_max_alpha", 255)
    if end_val < 10:
        score += 25
        feedback.append("Frame 20 is transparent (Character invisible).")
    elif end_val < 100:
        score += 10
        feedback.append(f"Frame 20 is partially transparent ({end_val}), expected invisible.")
    else:
        feedback.append(f"Frame 20 is still visible ({end_val}).")

    # Check Gradient (Smooth Transition)
    # Ideally: Val(5) > Val(10) > Val(15)
    val5 = f5.get("center_max_alpha", 0)
    val10 = f10.get("center_max_alpha", 0)
    val15 = f15.get("center_max_alpha", 0)
    
    if val5 > val10 and val10 > val15:
        score += 30
        feedback.append("Smooth fade-out transition detected.")
    elif val5 >= val15:
        # Partial credit for some decrease
        score += 15
        feedback.append("Transition detected but not perfectly smooth.")
    else:
        feedback.append("No clear fade-out transition detected in intermediate frames.")

    # Final Result
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }