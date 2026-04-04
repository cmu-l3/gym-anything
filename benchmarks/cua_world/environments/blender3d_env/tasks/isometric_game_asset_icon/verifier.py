#!/usr/bin/env python3
"""
Verifier for isometric_game_asset_icon task.
"""

import json
import os
import tempfile
import math

def verify_isometric_icon(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Extract data
    render_exists = result.get('render_exists', False)
    img_data = result.get('image_analysis') or {}
    scene_data = result.get('scene_data') or {}
    blend_exists = result.get('blend_exists', False)
    
    # 1. Image File Checks (40 pts)
    if render_exists:
        if result.get('render_created_during_task', False):
            score += 10
            feedback.append("Render file created during task.")
        else:
            feedback.append("Render file timestamp issue.")

        # Resolution (10 pts)
        if img_data.get('width') == 512 and img_data.get('height') == 512:
            score += 10
            feedback.append("Resolution is 512x512.")
        else:
            feedback.append(f"Resolution mismatch: {img_data.get('width')}x{img_data.get('height')}.")

        # Transparency/Alpha (20 pts)
        if img_data.get('has_alpha'):
            score += 10
            feedback.append("Alpha channel present.")
            # Check content
            if img_data.get('corner_transparent'):
                score += 5
                feedback.append("Background appears transparent.")
            if img_data.get('center_opaque'):
                score += 5
                feedback.append("Subject appears visible.")
        else:
            feedback.append("No alpha channel found (image is opaque).")
    else:
        feedback.append("No rendered image found.")

    # 2. Scene/Blend File Checks (60 pts)
    if blend_exists and scene_data:
        # Camera Type (15 pts)
        cam = scene_data.get('camera', {})
        if cam.get('type') == 'ORTHO':
            score += 15
            feedback.append("Camera is Orthographic.")
        else:
            feedback.append(f"Camera type is {cam.get('type')}, expected ORTHO.")

        # Camera Angles (15 pts)
        rot = cam.get('rotation_euler', [0, 0, 0]) # XYZ
        # Blender Euler is typically XYZ.
        # Target: X ~ 54.7, Z ~ 45.0
        # Allow +/- 2 degrees
        x_ok = abs(rot[0] - 54.7) < 3.0
        z_ok = abs(rot[2] - 45.0) < 3.0
        
        # Check alternate angles (corner views)
        # Z could be 45, 135, 225, 315 (-45, etc)
        z_mod = rot[2] % 360
        z_is_corner = any(abs(z_mod - angle) < 3.0 for angle in [45, 135, 225, 315])
        
        if x_ok and z_is_corner:
            score += 15
            feedback.append("Isometric angles correct.")
        else:
            feedback.append(f"Camera angles incorrect (X:{rot[0]:.1f}, Z:{rot[2]:.1f}).")

        # Render Settings (10 pts)
        if scene_data.get('film_transparent'):
            score += 10
            feedback.append("Film Transparency enabled in settings.")
        else:
            feedback.append("Film Transparency NOT enabled in settings.")

        # Background Removal (10 pts)
        # We check if the floor is visible in render
        if not scene_data.get('floor_visible_render', True):
            score += 10
            feedback.append("Floor object hidden/removed.")
        else:
            feedback.append("Floor object still visible in render.")
            
        # Saved blend file points (10 pts)
        score += 10
        feedback.append("Blend file saved.")

    else:
        feedback.append("Blend file not saved or unreadable - cannot verify camera settings.")

    # Final logic
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }