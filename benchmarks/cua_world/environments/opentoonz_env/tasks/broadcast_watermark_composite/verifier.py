#!/usr/bin/env python3
import json
import os
import tempfile
import logging
import numpy as np
from PIL import Image

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_broadcast_watermark_composite(traj, env_info, task_info):
    """
    Verifies that the agent composited a watermark logo into the bottom-right corner
    with transparency and scaling.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Scoring Variables
    score = 0
    feedback = []
    
    # Criterion 1: Output Generation (20 pts)
    file_count = result_data.get("file_count", 0)
    files_new = result_data.get("files_created_during_task", False)
    
    if file_count >= 20:
        score += 10
        feedback.append(f"Rendered {file_count} frames (Pass)")
    elif file_count > 0:
        score += 5
        feedback.append(f"Rendered only {file_count} frames (Partial)")
    else:
        feedback.append("No frames rendered")

    if files_new:
        score += 10
        feedback.append("Files created during task session (Pass)")
    else:
        feedback.append("Files not created during task (Fail)")

    # Criterion 2: visual Verification (80 pts)
    # We need to retrieve the verification frame
    frame_exists = result_data.get("verification_frame_exists", False)
    if not frame_exists:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback) + " | No output frame found for verification."}

    temp_img = tempfile.NamedTemporaryFile(delete=False, suffix=".png")
    try:
        copy_from_env("/tmp/verification_frame.png", temp_img.name)
        img = Image.open(temp_img.name).convert("RGBA")
        width, height = img.size
        arr = np.array(img)
        
        # --- Region Analysis ---
        
        # Define Regions
        # Bottom-Right (10% of width/height)
        br_x = int(width * 0.90)
        br_y = int(height * 0.90)
        region_br = arr[br_y:, br_x:]
        
        # Center (Safe zone, should NOT have watermark)
        # Center 20% box
        cx_start = int(width * 0.4)
        cx_end = int(width * 0.6)
        cy_start = int(height * 0.4)
        cy_end = int(height * 0.6)
        region_center = arr[cy_start:cy_end, cx_start:cx_end]

        # --- Color Detection Logic ---
        # The logo is Red (255, 0, 0). 
        # With 50% opacity, it will blend with background.
        # If BG is white: (255, 128, 128). If BG is transparent: (255, 0, 0, 128).
        # We look for elevated Red channel significantly higher than Green/Blue, 
        # OR pure red with alpha.
        
        def detect_red_influence(region):
            # Calculate mean R, G, B, A
            means = np.mean(region, axis=(0,1))
            r, g, b, a = means[0], means[1], means[2], means[3]
            
            # Check for redness dominance: R > G + threshold and R > B + threshold
            is_red_dominant = (r > (g + 20)) and (r > (b + 20))
            return is_red_dominant, means

        has_watermark, br_means = detect_red_influence(region_br)
        center_cluttered, center_means = detect_red_influence(region_center)

        # --- Opacity/Blending Logic ---
        # If it's pure red (255, 0, 0) and Alpha is 255, they missed the opacity step.
        # If R is high but G/B are also high (pinkish), that indicates blending over white.
        # If Alpha is < 250, that indicates transparency.
        
        is_transparent = False
        if br_means[3] < 250: # Direct Alpha check
            is_transparent = True
        elif br_means[1] > 50 and br_means[2] > 50: # Blending check (pinkish over white)
            is_transparent = True
            
        # Scoring Visuals
        
        # 3. Watermark Position (30 pts)
        if has_watermark:
            score += 30
            feedback.append("Watermark detected in bottom-right corner")
        else:
            feedback.append(f"No watermark detected in bottom-right (R:{br_means[0]:.1f} G:{br_means[1]:.1f} B:{br_means[2]:.1f})")

        # 4. Watermark Scaling/Safety (20 pts)
        if not center_cluttered:
            score += 20
            feedback.append("Center of frame is clear (scaling good)")
        else:
            feedback.append("Watermark appears to obstruct center of frame")

        # 5. Opacity Check (30 pts)
        if has_watermark:
            if is_transparent:
                score += 30
                feedback.append("Transparency/Blending detected")
            else:
                # If pure red opaque, partial credit
                score += 10
                feedback.append("Watermark is opaque (missed opacity requirement)")
        else:
            feedback.append("Cannot check opacity (no watermark)")

    except Exception as e:
        feedback.append(f"Image analysis failed: {str(e)}")
    finally:
        if os.path.exists(temp_img.name):
            os.unlink(temp_img.name)

    passed = (score >= 60) and files_new
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }