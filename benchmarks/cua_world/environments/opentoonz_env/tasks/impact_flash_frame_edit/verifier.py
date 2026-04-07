#!/usr/bin/env python3
import json
import os
import tempfile
import logging
import numpy as np
from PIL import Image

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_impact_flash_frame(traj, env_info, task_info):
    """
    Verifies the impact_flash_frame_edit task.
    
    Criteria:
    1. Output sequence exists (frames 1-24 approximately).
    2. Frame 12 exists and is predominantly RED.
    3. Frames 11 and 13 exist and are NOT predominantly RED (to ensure it's a single frame flash).
    4. Files were created during the task.
    """
    
    # 1. Setup and Load Basic Results
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    # Load result JSON
    result_json_path = tempfile.mktemp()
    try:
        copy_from_env("/tmp/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(result_json_path):
            os.remove(result_json_path)

    # 2. Extract Paths
    frame_11_path = result.get("frame_11_path", "")
    frame_12_path = result.get("frame_12_path", "")
    frame_13_path = result.get("frame_13_path", "")
    total_count = result.get("total_png_count", 0)
    files_fresh = result.get("files_created_during_task", False)

    score = 0
    feedback = []
    
    # Scoring - Criterion 1: Sequence Existence (20 pts)
    if total_count >= 24:
        score += 20
        feedback.append("Full frame sequence found.")
    elif total_count > 0:
        score += 10
        feedback.append(f"Partial sequence found ({total_count} frames).")
    else:
        feedback.append("No output frames found.")
        return {"passed": False, "score": 0, "feedback": "No output frames found."}

    # Scoring - Criterion 2: Freshness (10 pts)
    if files_fresh:
        score += 10
    else:
        feedback.append("Warning: Output files timestamp predates task start.")

    # Helper to analyze color
    def get_avg_color(remote_path):
        if not remote_path:
            return None
        local_path = tempfile.mktemp(suffix=".png")
        try:
            copy_from_env(remote_path, local_path)
            img = Image.open(local_path).convert("RGB")
            # Resize for speed
            img = img.resize((100, 100))
            arr = np.array(img)
            # Calculate average RGB
            avg_color = np.mean(arr, axis=(0, 1))
            return avg_color
        except Exception as e:
            logger.error(f"Error analyzing image {remote_path}: {e}")
            return None
        finally:
            if os.path.exists(local_path):
                os.remove(local_path)

    # Scoring - Criterion 3: Frame 12 is RED (40 pts)
    f12_color = get_avg_color(frame_12_path)
    frame_12_is_red = False
    
    if f12_color is not None:
        r, g, b = f12_color
        # Expect High Red, Low Green/Blue
        # Red > 200, G < 100, B < 100 is a safe threshold for "solid red"
        if r > 180 and g < 100 and b < 100:
            score += 40
            frame_12_is_red = True
            feedback.append(f"Frame 12 is correctly Red (RGB: {int(r)},{int(g)},{int(b)}).")
        else:
            feedback.append(f"Frame 12 is not Red (RGB: {int(r)},{int(g)},{int(b)}).")
    else:
        feedback.append("Frame 12 file missing or unreadable.")

    # Scoring - Criterion 4: Neighbor Frames are NOT Red (30 pts)
    # This proves they inserted a *single* frame, not just colored the whole video
    neighbors_ok = True
    
    for fname, path in [("Frame 11", frame_11_path), ("Frame 13", frame_13_path)]:
        color = get_avg_color(path)
        if color is not None:
            r, g, b = color
            # If neighbor is also red, penalty
            if r > 180 and g < 100 and b < 100:
                neighbors_ok = False
                feedback.append(f"{fname} is also Red! Should be normal animation.")
            else:
                # Good
                pass
        else:
            # If neighbor is missing, we can't verify continuity, partial penalty
            neighbors_ok = False
            feedback.append(f"{fname} missing.")
            
    if neighbors_ok and frame_11_path and frame_13_path:
        score += 30
        feedback.append("Neighbor frames preserve animation correctly.")
    elif neighbors_ok:
        # Files missing but existing ones weren't red
        score += 10
        feedback.append("Neighbor frames check incomplete (files missing).")
    else:
        feedback.append("Impact frame incorrectly extends to neighbors.")

    # Final Pass Check
    # Must have sequence, frame 12 red, and fresh files
    passed = (score >= 60) and frame_12_is_red and files_fresh

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }