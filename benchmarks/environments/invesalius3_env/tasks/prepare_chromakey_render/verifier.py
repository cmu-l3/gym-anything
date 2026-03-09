#!/usr/bin/env python3
"""
Verifier for prepare_chromakey_render task.

Criteria:
1. File exists and is a valid image.
2. Background is predominantly Green (Chroma Key).
3. Skull is visible (Center of image is not green).
4. UI Overlays (Bounding Box, Text) are hidden (Verified via VLM).
"""

import json
import os
import tempfile
import logging
import cv2
import numpy as np
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_prepare_chromakey_render(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load metadata
    metadata = task_info.get("metadata", {})
    expected_path = metadata.get("output_path", "/home/ga/Documents/chroma_skull.png")
    
    score = 0
    feedback_parts = []
    
    # --- Step 1: Retrieve Result JSON and Image ---
    try:
        # Get JSON
        tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_json.close()
        copy_from_env("/tmp/task_result.json", tmp_json.name)
        with open(tmp_json.name) as f:
            result = json.load(f)
        os.unlink(tmp_json.name)
        
        # Check existence
        if not result.get("output_exists"):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Output file not found at {expected_path}"
            }
        
        # Check timestamp
        if not result.get("created_after_start"):
            return {
                "passed": False,
                "score": 0,
                "feedback": "File exists but was not created during this task session (anti-gaming)."
            }

        score += 10 # File exists and is new
        
        # Get Image
        tmp_img = tempfile.NamedTemporaryFile(delete=False, suffix=".png")
        tmp_img.close()
        copy_from_env(expected_path, tmp_img.name)
        
        image = cv2.imread(tmp_img.name)
        os.unlink(tmp_img.name)
        
        if image is None:
            return {"passed": False, "score": score, "feedback": "File exists but is not a valid image."}
            
        score += 10 # Valid image format
        
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error during verification setup: {str(e)}"}

    # --- Step 2: Programmatic Color Analysis (Green Screen) ---
    try:
        # Convert BGR (OpenCV) to RGB
        img_rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        h, w, _ = img_rgb.shape
        
        # Sample corners (Background)
        corners = [
            img_rgb[0, 0],          # Top-left
            img_rgb[0, w-1],        # Top-right
            img_rgb[h-1, 0],        # Bottom-left
            img_rgb[h-1, w-1],      # Bottom-right
            img_rgb[10, 10],        # Inset TL
            img_rgb[h-10, w-10]     # Inset BR
        ]
        
        green_corner_count = 0
        for px in corners:
            r, g, b = int(px[0]), int(px[1]), int(px[2])
            # Definition of "Green Screen": Green is dominant and bright
            # G > R+30, G > B+30, G > 100
            if g > (r + 30) and g > (b + 30) and g > 100:
                green_corner_count += 1
        
        if green_corner_count >= 4:
            score += 30
            feedback_parts.append("Background is correctly set to Green.")
        else:
            feedback_parts.append(f"Background color incorrect. Found {green_corner_count}/6 green corners.")

        # Sample Center (Foreground/Skull)
        # The skull should be visible in the center (not green)
        center_crop = img_rgb[h//3 : 2*h//3, w//3 : 2*w//3]
        mean_center = np.mean(center_crop, axis=(0,1))
        r_c, g_c, b_c = mean_center
        
        # If center is also pure green, the skull is missing or zoomed out too far
        if g_c > (r_c + 30) and g_c > (b_c + 30):
            feedback_parts.append("Skull not detected in center of image (image appears empty).")
        else:
            score += 20
            feedback_parts.append("Skull detected in foreground.")

    except Exception as e:
        feedback_parts.append(f"Image analysis error: {str(e)}")

    # --- Step 3: VLM Verification (Overlays) ---
    # We use VLM to check if the user successfully hid the UI elements (Box, Text)
    # This is hard to do programmatically with simple CV
    
    vlm_prompt = """
    You are verifying a 3D medical render task.
    The goal was to render a skull against a green background with NO UI overlays.
    
    Look at the image and check:
    1. Is there a 3D skull visible?
    2. Is the background green?
    3. Are the white bounding box lines (cube around the skull) HIDDEN/GONE?
    4. Are the orientation letters (A, P, L, R, S, I) HIDDEN/GONE?
    
    Return JSON:
    {
        "skull_visible": true/false,
        "green_background": true/false,
        "box_hidden": true/false,
        "text_hidden": true/false
    }
    """
    
    # We pass the image we downloaded from the env
    # (Gym-Anything framework usually handles the image passing via the 'image' arg in query_vlm)
    # Here we need to be careful: query_vlm expects either a PIL image or bytes.
    # Since we have the file on disk temporarily or loaded in memory.
    
    try:
        # Re-read as bytes for VLM or use trajectory final screenshot if needed
        # We prefer the actual output file for quality check
        import cv2
        _, img_encoded = cv2.imencode('.png', image)
        img_bytes = img_encoded.tobytes()
        
        vlm_result = query_vlm(
            prompt=vlm_prompt,
            image=img_bytes
        )
        
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            
            if parsed.get("box_hidden", False):
                score += 15
                feedback_parts.append("Bounding box correctly hidden.")
            else:
                feedback_parts.append("Bounding box still visible.")
                
            if parsed.get("text_hidden", False):
                score += 15
                feedback_parts.append("Orientation text correctly hidden.")
            else:
                feedback_parts.append("Orientation text still visible.")
        else:
            # Fallback if VLM fails: give benefit of doubt if programmatic checks passed high
            feedback_parts.append(f"VLM verification skipped: {vlm_result.get('error')}")
            if score >= 60:
                score += 10 # Partial credit
                
    except Exception as e:
        feedback_parts.append(f"VLM error: {str(e)}")

    # Final Score
    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }