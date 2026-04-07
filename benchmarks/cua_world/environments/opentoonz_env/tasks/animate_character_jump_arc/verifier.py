#!/usr/bin/env python3
import json
import os
import tempfile
import cv2
import numpy as np

def calculate_centroid(image_path):
    """
    Calculates the (x, y) centroid of non-transparent/non-white pixels.
    Returns None if image is empty or invalid.
    """
    if not os.path.exists(image_path):
        return None
    
    # Load image (unchanged to keep alpha if present)
    img = cv2.imread(image_path, cv2.IMREAD_UNCHANGED)
    if img is None:
        return None

    h, w = img.shape[:2]
    
    # Create a mask of "content" pixels
    # If image has alpha channel (4 channels)
    if img.shape[2] == 4:
        alpha = img[:, :, 3]
        # Content is where alpha > 10
        y_indices, x_indices = np.where(alpha > 10)
    else:
        # If RGB, assume white background or check for non-white pixels
        # Convert to grayscale
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        # In OpenToonz renders, background might be white (255) or black (0) depending on settings
        # Usually checking deviation from background color is safer.
        # Let's assume content is not pure white (255) if it's a drawing on white.
        # Or not pure black (0) if on black.
        # Safe bet: compute variance or edges?
        # Simple approach: Threshold. Assume drawing is darker than white bg.
        _, thresh = cv2.threshold(gray, 240, 255, cv2.THRESH_BINARY_INV)
        y_indices, x_indices = np.where(thresh > 0)

    if len(x_indices) == 0 or len(y_indices) == 0:
        return None

    # Calculate centroid
    cx = int(np.mean(x_indices))
    cy = int(np.mean(y_indices))
    
    return (cx, cy)

def verify_animate_character_jump_arc(traj, env_info, task_info):
    """
    Verifies that the character moves in a parabolic arc (Left->Right, Low->High->Low).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []

    # 2. Check File Count (20 pts)
    file_count = result.get("file_count", 0)
    created_during = result.get("created_during_task", False)
    
    if file_count >= 24:
        score += 20
        feedback.append("Rendered 24+ frames.")
    elif file_count > 0:
        score += 10
        feedback.append(f"Rendered partial frames ({file_count}).")
    else:
        return {"passed": False, "score": 0, "feedback": "No frames rendered."}

    # 3. Check Freshness (10 pts)
    if created_during:
        score += 10
        feedback.append("Files created during task.")
    else:
        feedback.append("Files seem old (pre-existing?).")

    # 4. Analyze Trajectory (70 pts total)
    # We need to copy the images locally to analyze them with opencv
    frames = ["frame_start_path", "frame_mid_path", "frame_end_path"]
    centroids = []
    
    for key in frames:
        remote_path = result.get(key)
        if not remote_path:
            centroids.append(None)
            continue
            
        local_img = tempfile.NamedTemporaryFile(delete=False, suffix=".png")
        local_path = local_img.name
        local_img.close()
        
        try:
            copy_from_env(remote_path, local_path)
            c = calculate_centroid(local_path)
            centroids.append(c)
        except Exception:
            centroids.append(None)
        finally:
            if os.path.exists(local_path):
                os.unlink(local_path)

    p_start, p_mid, p_end = centroids

    # Analysis Logic
    if None in [p_start, p_mid, p_end]:
        feedback.append("Could not detect character in one or more keyframes (Start, Mid, End). Ensure visible rendering.")
        # Fail early if we can't see the character
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    sx, sy = p_start
    mx, my = p_mid
    ex, ey = p_end

    feedback.append(f"Positions detected - Start:({sx},{sy}) Mid:({mx},{my}) End:({ex},{ey})")

    # Horizontal Motion (Left -> Right) (25 pts)
    # Expect Start X < Mid X < End X
    # Add small tolerance/buffer
    horizontal_passed = False
    if sx < mx and mx < ex:
        # Check for significant movement
        if (ex - sx) > 100: # Moved at least 100px
            score += 25
            horizontal_passed = True
            feedback.append("Horizontal motion correct (Left to Right).")
        else:
            feedback.append("Horizontal movement too small.")
    else:
        feedback.append(f"Horizontal motion incorrect (X coords: {sx} -> {mx} -> {ex}).")

    # Vertical Motion (Jump Arc) (35 pts)
    # Expect Mid Y < Start Y AND Mid Y < End Y (In images, smaller Y is higher)
    # Require a significant jump height (e.g., 50px difference)
    vertical_passed = False
    jump_height_start = sy - my
    jump_height_end = ey - my
    
    if jump_height_start > 30 and jump_height_end > 30:
        score += 35
        vertical_passed = True
        feedback.append("Vertical arc correct (Jumped up and landed).")
    elif jump_height_start > 30:
        score += 15
        feedback.append("Character jumped up but didn't come down (or landed much higher).")
    else:
        feedback.append(f"Vertical motion flat or linear (Y coords: {sy} -> {my} -> {ey}).")

    # Final Pass Check
    # Need horizontal AND vertical success, plus files existing
    passed = horizontal_passed and vertical_passed and file_count >= 24

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }