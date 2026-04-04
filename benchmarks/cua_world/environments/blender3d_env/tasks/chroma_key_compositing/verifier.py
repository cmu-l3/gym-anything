#!/usr/bin/env python3
"""
Verifier for chroma_key_compositing task.

Scores based on:
1. Node Setup (25 pts): Correct nodes used in Blender.
2. Render Config (20 pts): PNG + RGBA settings.
3. Pixel Verification (45 pts): Analyzes the output image for transparency in background and opacity in subject.
4. File Existence (10 pts): Output files present.
"""

import json
import os
import sys
import tempfile
import logging
from PIL import Image

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chroma_key_compositing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata for regions (coordinates [x, y])
    # The default image (Dino) has subject in center, background at edges
    metadata = task_info.get('metadata', {})
    
    # Coordinate validation points (Top-Left is 0,0)
    # Background point (Top-Left quadrant)
    bg_point = metadata.get('background_region', [100, 100])
    # Subject point (Center)
    subj_point = metadata.get('subject_region', [960, 540]) 
    
    min_alpha_subject = metadata.get('min_alpha_subject', 200)
    max_alpha_background = metadata.get('max_alpha_background', 20)

    score = 0
    feedback = []

    # 1. Get Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Verify File Existence (10 pts)
    if result.get("blend_exists"):
        score += 5
    else:
        feedback.append("Blender project file not saved.")

    if result.get("render_exists"):
        score += 5
    else:
        feedback.append("Render output not saved.")

    # 3. Analyze Scene Structure (45 pts total)
    analysis = result.get("scene_analysis", {})
    render_cfg = analysis.get("render", {})
    comp_cfg = analysis.get("compositor", {})

    # 3a. Node Setup (25 pts)
    if comp_cfg.get("use_nodes"):
        score += 5
        if comp_cfg.get("has_keying_node"):
            score += 10
        else:
            feedback.append("No Chroma Key/Keying node detected in Compositor.")
        
        if comp_cfg.get("links_valid"):
            score += 10
        else:
            feedback.append("Compositor nodes are not correctly linked (Input -> Output).")
    else:
        feedback.append("Compositor 'Use Nodes' is not enabled.")

    # 3b. Render Settings (20 pts)
    if render_cfg.get("file_format") == 'PNG':
        score += 10
    else:
        feedback.append(f"Wrong file format: {render_cfg.get('file_format')}, expected PNG.")

    if render_cfg.get("color_mode") == 'RGBA':
        score += 10
    else:
        feedback.append(f"Wrong color mode: {render_cfg.get('color_mode')}, expected RGBA for transparency.")

    # 4. Pixel Verification (45 pts)
    # We need to pull the rendered image to check pixels
    if result.get("render_exists"):
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env("/home/ga/BlenderProjects/keyed_subject.png", temp_img.name)
            
            with Image.open(temp_img.name) as img:
                width, height = img.size
                
                # Verify Format
                if img.mode != 'RGBA':
                    feedback.append("Rendered image does not have an Alpha channel.")
                else:
                    # Check Background Transparency (25 pts)
                    # We check a 5x5 patch around the target point to be safe against noise
                    bg_x, bg_y = bg_point
                    bg_alpha_sum = 0
                    count = 0
                    
                    # Ensure coords are within bounds
                    if bg_x < width and bg_y < height:
                        pixel = img.getpixel((bg_x, bg_y))
                        alpha = pixel[3]
                        
                        if alpha <= max_alpha_background:
                            score += 25
                        else:
                            feedback.append(f"Background removal failed: Alpha at {bg_point} is {alpha} (expected < {max_alpha_background}).")
                    
                    # Check Subject Opacity (20 pts)
                    subj_x, subj_y = subj_point
                    if subj_x < width and subj_y < height:
                        pixel = img.getpixel((subj_x, subj_y))
                        alpha = pixel[3]
                        
                        if alpha >= min_alpha_subject:
                            score += 20
                        else:
                            feedback.append(f"Subject opacity failed: Alpha at {subj_point} is {alpha} (expected > {min_alpha_subject}).")

        except Exception as e:
            feedback.append(f"Image verification failed: {e}")
        finally:
            if os.path.exists(temp_img.name):
                os.unlink(temp_img.name)
    else:
        feedback.append("Cannot verify pixels - render file missing.")

    # Final Score Calculation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback) if feedback else "Task completed successfully."
    }