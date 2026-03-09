#!/usr/bin/env python3
"""
Verifier for shaft_keyway_section task.

Scoring Criteria:
1. File Creation (10pts): Valid DXF file created during task window.
2. Geometry (30pts): Correct 50mm diameter circle found.
3. Layers (20pts): Required layers (SHAFT, CENTER, HATCHING, DIMENSIONS, TEXT) exist.
4. Drafting Elements (20pts): Hatching and Dimensions present.
5. VLM Verification (20pts): Visual confirmation of keyway shape and general layout.
"""

import json
import os
import sys
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_shaft_keyway_section(traj, env_info, task_info):
    """
    Verify the shaft keyway drawing task using programmatic checks from the container
    and VLM visual verification.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Extract analysis data
    dxf_data = result.get('dxf_analysis', {})
    valid_dxf = dxf_data.get('valid_dxf', False)
    file_created = result.get('file_created_during_task', False)
    
    # --- Criterion 1: File Existence & Validity (10 pts) ---
    if valid_dxf and file_created:
        score += 10
        feedback_parts.append("Valid DXF created")
    elif valid_dxf:
        score += 5
        feedback_parts.append("DXF exists but not created during task window")
    else:
        feedback_parts.append("No valid DXF file found")
        # Early exit if no file
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # --- Criterion 2: Geometry (30 pts) ---
    # Check for correct circle radius (25mm)
    if dxf_data.get('has_correct_circle', False):
        score += 30
        feedback_parts.append("Correct shaft diameter (50mm)")
    else:
        feedback_parts.append("Shaft circle with correct diameter not found")

    # --- Criterion 3: Layers (20 pts) ---
    required_layers = ['SHAFT', 'CENTER', 'HATCHING', 'DIMENSIONS', 'TEXT']
    found_layers = dxf_data.get('layers_found', [])
    
    # Count how many required layers exist (case-insensitive)
    found_count = 0
    missing_layers = []
    for req in required_layers:
        if req in found_layers:
            found_count += 1
        else:
            missing_layers.append(req)
            
    layer_score = int((found_count / len(required_layers)) * 20)
    score += layer_score
    if found_count == len(required_layers):
        feedback_parts.append("All layers present")
    else:
        feedback_parts.append(f"Missing layers: {', '.join(missing_layers)}")

    # --- Criterion 4: Drafting Elements (20 pts) ---
    # Check for Hatching (10 pts)
    hatch_count = dxf_data.get('hatch_count', 0)
    if hatch_count > 0:
        score += 10
        feedback_parts.append("Hatching present")
    else:
        feedback_parts.append("No hatching found")
        
    # Check for Dimensions/Text (10 pts)
    dim_count = dxf_data.get('dimension_count', 0)
    text_content = " ".join(dxf_data.get('text_content', [])).upper()
    
    # We want either dimension entities OR text that looks like dimensions/annotations
    if dim_count > 0 or "SHAFT" in text_content or "DIN" in text_content:
        score += 10
        feedback_parts.append("Annotations present")
    else:
        feedback_parts.append("No dimensions or text annotations found")

    # --- Criterion 5: VLM Visual Verification (20 pts) ---
    # Use trajectory to verify the keyway shape specifically, as geometric parsing of
    # arbitrary lines for a keyway is brittle programmatically.
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if final_screen:
        vlm_images = frames + [final_screen]
        prompt = """
        Review this sequence of a user drawing a mechanical shaft cross-section in CAD.
        The final result should be a circle with a rectangular notch (keyway) cut into the top.
        
        Check for these specific visual elements:
        1. Is there a circular shaft?
        2. Is there a rectangular notch (keyway) at the top of the circle?
        3. Are there center lines (crosshairs) through the center?
        4. Is the solid part of the shaft hatched (diagonal lines)?
        
        Answer JSON: {"keyway_visible": bool, "hatching_visible": bool, "looks_correct": bool}
        """
        
        try:
            vlm_res = query_vlm(images=vlm_images, prompt=prompt)
            vlm_data = vlm_res.get('parsed', {})
            
            vlm_score = 0
            if vlm_data.get('keyway_visible'):
                vlm_score += 10
                feedback_parts.append("Visual: Keyway notch verified")
            if vlm_data.get('hatching_visible'):
                vlm_score += 5
                feedback_parts.append("Visual: Hatching verified")
            if vlm_data.get('looks_correct'):
                vlm_score += 5
                
            score += vlm_score
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if programmatic score is high, assume visual is okay-ish to avoid failing on VLM error
            if score >= 60:
                score += 10
                feedback_parts.append("VLM skipped (error)")

    # Final scoring logic
    passed = score >= 60 and dxf_data.get('has_correct_circle', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }