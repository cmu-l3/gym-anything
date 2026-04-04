#!/usr/bin/env python3
"""
Verifier for publication_skull_render task.

Scoring (100 points total):
  - File Requirements (40 pts):
    - Exists and is PNG: 10 pts
    - Created during task: 10 pts
    - Size > 100KB: 10 pts
    - Dimensions >= 800x600: 10 pts
  - Visual Requirements (Programmatic) (20 pts):
    - White background (corners check): 20 pts
  - VLM Verification (40 pts):
    - Skull surface visible: 20 pts
    - Frontal/Anterior view: 20 pts

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging
from PIL import Image
import numpy as np

# Import VLM utils from the framework
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logger = logging.getLogger(__name__)

def verify_publication_skull_render(traj, env_info, task_info):
    """Verify the publication quality skull render."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    min_size = metadata.get("min_file_size_bytes", 102400)
    min_w = metadata.get("min_width", 800)
    min_h = metadata.get("min_height", 600)
    bg_thresh = metadata.get("background_threshold", 230)

    score = 0
    feedback_parts = []
    
    # 1. Load JSON result from container
    try:
        tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_json.close()
        copy_from_env("/tmp/publication_skull_render_result.json", tmp_json.name)
        with open(tmp_json.name) as f:
            result = json.load(f)
        os.unlink(tmp_json.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}

    # 2. Basic File Checks (40 pts)
    file_exists = result.get("file_exists", False)
    is_png = result.get("is_png", False)
    
    if file_exists and is_png:
        score += 10
        feedback_parts.append("Valid PNG exists")
    else:
        feedback_parts.append("PNG file not found or invalid")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    if result.get("created_during_task", False):
        score += 10
        feedback_parts.append("Created during task")
    else:
        feedback_parts.append("File timestamp predates task (did you overwrite?)")

    file_size = result.get("file_size_bytes", 0)
    if file_size >= min_size:
        score += 10
        feedback_parts.append(f"Size OK ({file_size//1024}KB)")
    else:
        feedback_parts.append(f"File too small ({file_size//1024}KB)")

    w, h = result.get("width", 0), result.get("height", 0)
    if w >= min_w and h >= min_h:
        score += 10
        feedback_parts.append(f"Resolution OK ({w}x{h})")
    else:
        feedback_parts.append(f"Low resolution ({w}x{h})")

    # 3. Image Content Analysis (Host-side)
    # Copy the actual image file to analyze pixels
    image_score = 0
    try:
        tmp_img = tempfile.NamedTemporaryFile(delete=False, suffix=".png")
        tmp_img.close()
        copy_from_env("/home/ga/Documents/skull_frontal_pub.png", tmp_img.name)
        
        with Image.open(tmp_img.name) as img:
            img = img.convert("RGB")
            arr = np.array(img)
            
            # Check corners for white background
            # 20 pts for white background
            h_img, w_img, _ = arr.shape
            corners = [
                arr[0:10, 0:10],          # Top-left
                arr[0:10, w_img-10:w_img], # Top-right
                arr[h_img-10:h_img, 0:10], # Bottom-left
                arr[h_img-10:h_img, w_img-10:w_img] # Bottom-right
            ]
            
            white_corners = 0
            for c in corners:
                mean_color = np.mean(c, axis=(0,1))
                # Check if all channels are bright (>230)
                if np.all(mean_color > bg_thresh):
                    white_corners += 1
            
            if white_corners >= 3:
                score += 20
                feedback_parts.append(f"Background verified white ({white_corners}/4 corners)")
            else:
                feedback_parts.append(f"Background not white (only {white_corners}/4 corners bright)")

        os.unlink(tmp_img.name)
    except Exception as e:
        feedback_parts.append(f"Image analysis failed: {e}")

    # 4. VLM Verification (40 pts)
    # Use trajectory frames + output image for verification
    # If the output file exists, we prioritize checking that.
    
    vlm_prompt = """
    You are verifying a medical image task. 
    The user was asked to:
    1. Render a 3D skull (bone).
    2. Set the background to white.
    3. Orient the view to a standard ANTERIOR (Frontal) view (face forward).
    
    Look at the provided image (the output file).
    
    Respond in JSON:
    {
      "is_skull_visible": boolean,
      "is_background_white": boolean,
      "view_orientation": "anterior" | "lateral" | "posterior" | "superior" | "other",
      "is_frontal_view": boolean
    }
    """
    
    # We use the final exported image for VLM if available, otherwise final screenshot
    # Actually, we should check the exported file specifically because that's the deliverable.
    # We can pass the temp image path if the VLM tool supports local paths, or use the screenshot 
    # if we assume the screen matches the export. 
    # Since `query_vlm` usually takes the screenshot from trajectory or bytes, 
    # let's assume we use the final screenshot for context, but ideally we'd send the file.
    # Framework pattern: Use `get_final_screenshot(traj)`
    
    final_screen = get_final_screenshot(traj)
    
    if final_screen:
        vlm_res = query_vlm(
            prompt=vlm_prompt,
            image=final_screen
        )
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            
            # Criterion: Skull visible (20 pts)
            if parsed.get("is_skull_visible"):
                score += 20
                feedback_parts.append("VLM: Skull visible")
            else:
                feedback_parts.append("VLM: Skull NOT detected")
                
            # Criterion: Frontal View (20 pts)
            if parsed.get("is_frontal_view") or parsed.get("view_orientation") == "anterior":
                score += 20
                feedback_parts.append("VLM: Frontal view confirmed")
            else:
                feedback_parts.append(f"VLM: Incorrect orientation ({parsed.get('view_orientation', 'unknown')})")
        else:
            feedback_parts.append("VLM query failed")
            # Fallback points if programmatic checks were very strong? 
            # No, keep strict for now.
    else:
        feedback_parts.append("No screenshot for VLM verification")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }