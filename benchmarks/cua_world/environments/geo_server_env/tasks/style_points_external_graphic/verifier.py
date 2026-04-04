#!/usr/bin/env python3
"""Verifier for style_points_external_graphic task."""

import json
import tempfile
import os
import re

def verify_style_points_external_graphic(traj, env_info, task_info):
    """
    Verify creation of SVG, Style, and assignment to Layer.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/style_points_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. SVG Verification (20 points)
    # ------------------------------------------------------------------
    svg_found = result.get('svg_found', False)
    svg_content = result.get('svg_content', '').lower()
    
    if svg_found:
        score += 10
        feedback_parts.append("SVG file found")
        
        # Check content for yellow and star-like properties
        if 'yellow' in svg_content or '#ffff00' in svg_content or '#ff0' in svg_content:
            score += 5
            feedback_parts.append("SVG has yellow fill")
        else:
            feedback_parts.append("SVG missing yellow fill")
            
        if '<svg' in svg_content:
            score += 5
            feedback_parts.append("Valid SVG format")
    else:
        feedback_parts.append("SVG file 'star.svg' NOT found")

    # ------------------------------------------------------------------
    # 2. Style Creation Verification (20 points)
    # ------------------------------------------------------------------
    style_found = result.get('style_found', False)
    style_sld = result.get('style_sld', '')
    
    if style_found:
        score += 20
        feedback_parts.append(f"Style '{result.get('style_name')}' found")
    else:
        feedback_parts.append("Style 'star_marker' NOT found")

    # ------------------------------------------------------------------
    # 3. SLD Configuration (30 points)
    # ------------------------------------------------------------------
    if style_found and style_sld:
        sld_lower = style_sld.lower()
        
        # Check for ExternalGraphic
        if 'externalgraphic' in sld_lower:
            score += 10
            feedback_parts.append("SLD uses ExternalGraphic")
        else:
            feedback_parts.append("SLD does NOT use ExternalGraphic")
            
        # Check reference to star.svg
        if 'star.svg' in sld_lower:
            score += 10
            feedback_parts.append("SLD references 'star.svg'")
        else:
            feedback_parts.append("SLD does not reference 'star.svg'")
            
        # Check format
        if 'image/svg+xml' in sld_lower:
            score += 10
            feedback_parts.append("SLD specifies image/svg+xml format")
        else:
            feedback_parts.append("SLD missing correct format (image/svg+xml)")

    # ------------------------------------------------------------------
    # 4. Layer Assignment (20 points)
    # ------------------------------------------------------------------
    layer_correct = result.get('layer_style_correct', False)
    
    if layer_correct:
        score += 20
        feedback_parts.append("Layer 'ne_populated_places' uses 'star_marker' as default")
    else:
        current = result.get('layer_default_style', 'unknown')
        feedback_parts.append(f"Layer uses '{current}' instead of 'star_marker'")

    # ------------------------------------------------------------------
    # 5. WMS Functional Check (10 points)
    # ------------------------------------------------------------------
    wms_works = result.get('wms_works', False)
    wms_size = result.get('wms_size_bytes', 0)
    
    if wms_works and wms_size > 1000:
        score += 10
        feedback_parts.append("WMS rendering successful")
    elif wms_works:
        # File exists but small - might be blank or error image
        score += 5
        feedback_parts.append("WMS returned image but size is suspicious")
    else:
        feedback_parts.append("WMS GetMap request failed")

    # ------------------------------------------------------------------
    # VLM Verification (Anti-Gaming / Process Check)
    # ------------------------------------------------------------------
    # If using REST API exclusively without GUI (which is harder for this task due to SVG upload),
    # we might want to dock points if VLM confirms NO GUI usage.
    # However, SVG upload is complex via REST for agents, so GUI is likely.
    # We'll use VLM mainly to confirm they didn't just 'edit' an existing style to look like it.
    
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, num_samples=3)
        final = get_final_screenshot(traj)
        images = frames + ([final] if final else [])
        
        if images:
            vlm_res = query_vlm(
                images=images,
                prompt="Do these screenshots show a user editing a Style or SLD in GeoServer? Look for XML code or a Style Editor."
            )
            # We don't strictly penalize here, but logic could be added. 
            # For now, we rely on the specific file/content checks.

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }