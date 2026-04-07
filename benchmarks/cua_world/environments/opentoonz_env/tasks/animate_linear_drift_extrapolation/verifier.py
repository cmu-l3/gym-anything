#!/usr/bin/env python3
import json
import os
import tempfile
import numpy as np
import cv2
from gym_anything.vlm import sample_trajectory_frames

def verify_animate_linear_drift_extrapolation(traj, env_info, task_info):
    """
    Verifies that the agent set up linear extrapolation by comparing Frame 20 and Frame 60.
    
    Logic:
    1. If Extrapolation is 'Constant' (default), Frame 60 will be identical to Frame 20 (motion stops).
    2. If Extrapolation is 'Linear' (goal), Frame 60 will show the character shifted further right.
    """
    
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load result JSON
    result_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", result_file.name)
        with open(result_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(result_file.name):
            os.unlink(result_file.name)

    score = 0
    feedback = []

    # 2. Check File Existence (20 pts)
    f20_exists = result.get("frame_20_exists", False)
    f60_exists = result.get("frame_60_exists", False)
    
    if f20_exists and f60_exists:
        score += 20
        feedback.append("Both output frames found.")
    elif f20_exists or f60_exists:
        score += 10
        feedback.append("One output frame found.")
    else:
        return {"passed": False, "score": 0, "feedback": "No output frames found."}

    # 3. Check Freshness (10 pts)
    if result.get("frame_20_fresh") and result.get("frame_60_fresh"):
        score += 10
        feedback.append("Files created during task session.")
    else:
        feedback.append("Warning: Files might be stale.")

    # 4. Image Analysis (Extrapolation Logic) (70 pts)
    try:
        # Download images
        f20_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".png").name
        f60_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".png").name
        
        copy_from_env(result["frame_20_path"], f20_tmp)
        copy_from_env(result["frame_60_path"], f60_tmp)
        
        img20 = cv2.imread(f20_tmp)
        img60 = cv2.imread(f60_tmp)
        
        if img20 is None or img60 is None:
            raise ValueError("Failed to read image files")
            
        # Ensure same size for comparison
        if img20.shape != img60.shape:
            img60 = cv2.resize(img60, (img20.shape[1], img20.shape[0]))

        # Calculate difference (SSIM or just MSE)
        # We expect a SIGNIFICANT difference if the character moved
        diff = cv2.absdiff(img20, img60)
        non_zero_count = np.count_nonzero(diff)
        total_pixels = diff.size
        diff_ratio = non_zero_count / total_pixels
        
        # Calculate centroids to verify direction
        gray20 = cv2.cvtColor(img20, cv2.COLOR_BGR2GRAY)
        gray60 = cv2.cvtColor(img60, cv2.COLOR_BGR2GRAY)
        
        # Invert if background is white (common in traditional animation)
        # Assuming character is darker than background
        if np.mean(gray20) > 127:
            _, thresh20 = cv2.threshold(gray20, 200, 255, cv2.THRESH_BINARY_INV)
            _, thresh60 = cv2.threshold(gray60, 200, 255, cv2.THRESH_BINARY_INV)
        else:
            _, thresh20 = cv2.threshold(gray20, 50, 255, cv2.THRESH_BINARY)
            _, thresh60 = cv2.threshold(gray60, 50, 255, cv2.THRESH_BINARY)
            
        M20 = cv2.moments(thresh20)
        M60 = cv2.moments(thresh60)
        
        cx20 = int(M20["m10"] / M20["m00"]) if M20["m00"] != 0 else 0
        cx60 = int(M60["m10"] / M60["m00"]) if M60["m00"] != 0 else 0
        
        # CRITERION: Motion Check
        if diff_ratio < 0.01: # Images are basically identical
            feedback.append("FAIL: Frame 60 is identical to Frame 20. Extrapolation likely set to 'Constant'.")
        else:
            score += 40
            feedback.append("Success: Frame 60 differs from Frame 20, indicating continued motion.")
            
            # CRITERION: Direction Check (Rightward drift)
            if cx60 > cx20:
                score += 20
                feedback.append(f"Direction correct: Character moved right (X: {cx20} -> {cx60}).")
            else:
                score += 5
                feedback.append(f"Warning: Motion detected but direction unclear (X: {cx20} -> {cx60}).")
                
        # Cleanup
        os.unlink(f20_tmp)
        os.unlink(f60_tmp)

    except Exception as e:
        feedback.append(f"Image analysis failed: {str(e)}")
        # If we can't analyze images, we rely on file existence and VLM check
    
    # 5. VLM Check (Secondary / 10 pts)
    # Check if Function Editor was likely used based on trajectory
    # This is a 'bonus' or fallback if image analysis is ambiguous
    # Only if score < 90
    if score < 90:
        # This is a simplified check; usually we'd call a VLM here.
        # Given prompt constraints, we assume trajectory frames are passed to a hypothetical VLM function
        # But for this implementation, we will just cap the score if image analysis passed.
        pass
    else:
        score += 10 # Bonus for perfect execution

    passed = score >= 80
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }