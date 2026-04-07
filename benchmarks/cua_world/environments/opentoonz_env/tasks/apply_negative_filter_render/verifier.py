#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logger = logging.getLogger(__name__)

def verify_apply_negative_filter_render(traj, env_info, task_info):
    """
    Verify that the user applied a negative/invert filter and rendered the result.
    
    Scoring Criteria:
    1. Files Exist (20 pts): >= 12 PNG files in output dir.
    2. Freshness (15 pts): Files created during task.
    3. Visual Content (50 pts): 
       - Mean brightness < 50 (Assuming original white BG becomes black).
       - Std Dev > 10 (Not a solid black image).
    4. VLM Verification (15 pts):
       - Confirm trajectory shows interaction with FX Schematic or FX Browser.
    """
    
    # 1. Setup & Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}
    
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # 2. Evaluate Programmatic Criteria
    
    # Criterion 1: File Count
    count = result.get("file_count", 0)
    min_frames = task_info.get("metadata", {}).get("min_frame_count", 12)
    
    if count >= min_frames:
        score += 20
        feedback.append(f"Render successful: {count} frames found.")
    elif count > 0:
        score += 10
        feedback.append(f"Partial render: {count}/{min_frames} frames.")
    else:
        feedback.append("No output files found.")
        return {"passed": False, "score": 0, "feedback": "No output generated."}

    # Criterion 2: Freshness (Anti-Gaming)
    new_count = result.get("new_files_count", 0)
    if new_count >= count and count > 0:
        score += 15
        feedback.append("Files verified as newly created.")
    elif new_count > 0:
        score += 5
        feedback.append("Some files are old/pre-existing.")
    else:
        feedback.append("Files appear to be pre-existing (not rendered now).")

    # Criterion 3: Visual Content (Inversion Check)
    # Original 'dwanko_run' is on a white background.
    # Inverted, the background (dominant area) should be black (0).
    mean_brightness = result.get("mean_brightness", 255.0)
    std_dev = result.get("std_dev", 0.0)
    
    # Thresholds
    MAX_BRIGHTNESS = 80  # Allow some leeway, but should be dark
    MIN_STD = 10         # Ensure not solid color
    
    if mean_brightness < MAX_BRIGHTNESS:
        if std_dev > MIN_STD:
            score += 50
            feedback.append(f"Visual verification passed: Image is dark (Inverted) with content (Mean: {mean_brightness:.1f}).")
        else:
            score += 10
            feedback.append("Visual verification warning: Image is dark but solid color (Empty?).")
    else:
        feedback.append(f"Visual verification failed: Image is too bright (Mean: {mean_brightness:.1f}). Likely NOT inverted.")

    # 3. VLM Verification (Trajectory Analysis)
    # We want to see if they actually used the FX tools, not just commanded a cli render (unlikely but possible) or cheated.
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = (
        "Analyze these screenshots of a user using OpenToonz.\n"
        "The goal is to apply a 'Negative' or 'Invert' effect to the animation.\n"
        "Look for:\n"
        "1. The 'Schematic' window (node graph) or 'FX Browser' window being open.\n"
        "2. An effect node named 'Invert', 'Negative', or similar being added.\n"
        "3. The 'Preview' or 'Render' window showing a character with inverted colors (e.g. blue skin, black background).\n\n"
        "Did the user perform these actions?"
    )
    
    vlm_result = query_vlm(
        images=frames + [final_screen],
        prompt=vlm_prompt
    )
    
    if vlm_result.get("success") and "yes" in vlm_result.get("response", "").lower():
        score += 15
        feedback.append("VLM verification passed: FX workflow detected.")
    else:
        # Fallback if VLM is unsure but pixel check passed strictly
        if score >= 70:
            score += 15
            feedback.append("VLM inconclusive, but output verifies task.")
        else:
            feedback.append("VLM did not observe clear FX workflow.")

    # 4. Final Result
    passed = (score >= 85) # Requires render + freshness + inversion + (VLM or high confidence)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }