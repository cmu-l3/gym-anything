#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_extract_keyframe_transparent(traj, env_info, task_info):
    """
    Verifies that the agent successfully extracted a specific keyframe
    with a transparent background and correct resolution.
    """
    # 1. Setup and Load Results
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Task Failed: No result file generated."}
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "Task Failed: Result file corrupted."}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Define Success Criteria from Metadata (or defaults)
    metadata = task_info.get('metadata', {})
    expected_width = metadata.get('expected_width', 1280)
    expected_height = metadata.get('expected_height', 720)
    
    score = 0
    feedback = []

    # 3. Score Calculation
    
    # Criterion A: File Exists (15 pts)
    if result.get('output_exists'):
        score += 15
        feedback.append("Output file found.")
    else:
        feedback.append("No output file found in the specified directory.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion B: File Created During Task (10 pts) - Anti-gaming
    if result.get('created_during_task'):
        score += 10
        feedback.append("File was created during the task session.")
    else:
        feedback.append("File timestamp indicates it was not created during this session.")

    # Criterion C: Valid File Size (10 pts)
    # A 1280x720 PNG shouldn't be tiny unless it's empty
    if result.get('file_size_bytes', 0) > 1024: # > 1KB
        score += 10
    else:
        feedback.append("File size is suspiciously small (likely empty or corrupt).")

    # Criterion D: Resolution Check (25 pts)
    actual_w = result.get('image_width', 0)
    actual_h = result.get('image_height', 0)
    if actual_w == expected_width and actual_h == expected_height:
        score += 25
        feedback.append(f"Resolution matches target ({expected_width}x{expected_height}).")
    else:
        feedback.append(f"Incorrect resolution: {actual_w}x{actual_h} (Expected {expected_width}x{expected_height}).")

    # Criterion E: Transparency/Alpha Channel (40 pts total)
    mode = result.get('image_mode', '')
    has_transparency = result.get('has_transparency', False)
    
    # E1: Check Mode (25 pts)
    if mode == 'RGBA':
        score += 25
        feedback.append("Correct color mode (RGBA) with alpha channel.")
        
        # E2: Check Actual Transparency Data (15 pts)
        if has_transparency:
            score += 15
            feedback.append("Transparent pixels detected in alpha channel.")
        else:
            feedback.append("Image is RGBA but appears fully opaque (Background not removed?).")
    else:
        feedback.append(f"Incorrect color mode: {mode}. Expected RGBA.")

    # 4. Final Verification
    # Passing requires > 60 points AND specific key criteria (Resolution + Transparency)
    passed = (score >= 60) and (mode == 'RGBA') and (actual_w == expected_width) and (actual_h == expected_height)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }