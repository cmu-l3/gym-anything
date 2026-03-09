#!/usr/bin/env python3
"""Verifier for create_heatmap_rendering_transformation task."""

import json
import tempfile
import os

def verify_create_heatmap(traj, env_info, task_info):
    """Verify that a heatmap style was created, assigned, and rendered."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_style = metadata.get('expected_style_name', 'heatmap_population')
    min_colors = metadata.get('min_color_count', 4)

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_heatmap_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Verify integrity
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce mismatch"}
    except Exception:
        pass # Allow soft fail if nonce file missing in dev
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    score = 0
    feedback_parts = []

    # 1. Style Existence & Content (45 points)
    if result.get('style_found'):
        score += 15
        feedback_parts.append(f"Style '{expected_style}' created")
        
        if result.get('style_has_heatmap'):
            score += 15
            feedback_parts.append("SLD contains Heatmap transformation")
        else:
            feedback_parts.append("SLD missing 'vec:Heatmap' transformation")
            
        if result.get('style_has_pop_max'):
            score += 10
            feedback_parts.append("SLD references 'pop_max' attribute")
        
        if result.get('style_has_colormap'):
            score += 5
            feedback_parts.append("SLD contains ColorMap")
    else:
        feedback_parts.append(f"Style '{expected_style}' NOT found")

    # 2. Layer Association (15 points)
    if result.get('layer_associated'):
        score += 15
        feedback_parts.append("Style associated with layer")
    else:
        feedback_parts.append("Style NOT associated with 'ne:ne_populated_places'")

    # 3. Output Image (40 points)
    if result.get('image_exists'):
        if result.get('is_error_image'):
            feedback_parts.append("Output image is an OGC Service Exception (Error)")
        else:
            score += 10
            feedback_parts.append("Output image exists")
            
            # Dimensions
            width = int(result.get('image_width', 0))
            height = int(result.get('image_height', 0))
            if width == 800 and height == 400:
                score += 10
                feedback_parts.append("Image dimensions correct (800x400)")
            elif width > 0:
                score += 5
                feedback_parts.append(f"Image dimensions incorrect ({width}x{height})")
            
            # Colors (Heatmap check)
            colors = int(result.get('image_colors', 0))
            if colors >= min_colors:
                score += 20
                feedback_parts.append(f"Image shows rendering content ({colors} unique colors)")
            elif colors > 1:
                score += 10
                feedback_parts.append(f"Image low color count ({colors}), likely blank or single color")
            else:
                feedback_parts.append("Image is blank/monochrome")
    else:
        feedback_parts.append("No output image found")

    # 4. VLM Verification (Bonus/Penalty)
    # If using API only (no GUI interaction), we might want to penalize if the task implies GUI use.
    # However, for now, we'll verify the trajectory shows work.
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, num_samples=3)
        if frames:
            vlm_res = query_vlm(
                images=frames,
                prompt="Do these screenshots show a user editing an SLD style or XML code in GeoServer? Return JSON: {'editing_style': bool}"
            )
            if vlm_res and vlm_res.get('success'):
                if vlm_res.get('parsed', {}).get('editing_style'):
                    feedback_parts.append("VLM confirmed style editing UI")
                else:
                    feedback_parts.append("VLM did not detect style editor usage")

    passed = score >= 60 and result.get('style_has_heatmap')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }