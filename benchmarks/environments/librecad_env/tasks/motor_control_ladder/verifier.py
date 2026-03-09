#!/usr/bin/env python3
"""
Verifier for motor_control_ladder task.

Criteria:
1. File Creation (Anti-gaming): File must be created/modified during task window.
2. Structure (DXF Analysis):
   - Specific layers must exist with correct colors.
   - Text entities must contain specific labels.
   - Geometry must resemble a ladder diagram (vertical rails, horizontal rungs).
3. Visual (VLM):
   - Verify workflow and final appearance.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_motor_control_ladder(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --------------------------------------------------------------------------
    # 1. File Existence & Anti-Gaming (20 points)
    # --------------------------------------------------------------------------
    dxf_data = result.get('dxf_analysis', {})
    file_created = result.get('file_created_during_task', False)
    
    if dxf_data.get('exists') and dxf_data.get('valid_dxf'):
        if file_created:
            score += 20
            feedback.append("Valid DXF file created during task.")
        else:
            score += 5
            feedback.append("DXF file exists but was NOT modified during task (stale data?).")
    else:
        return {"passed": False, "score": 0, "feedback": "No valid DXF file found."}

    # --------------------------------------------------------------------------
    # 2. Layer Structure Verification (30 points)
    # --------------------------------------------------------------------------
    layers = dxf_data.get('layers', {})
    required_layers = {
        'POWER': 1,    # Red
        'RUNGS': 2,    # Yellow
        'SYMBOLS': 3,  # Green
        'TEXT': 7      # White/Black
    }
    
    layer_score = 0
    for name, color_idx in required_layers.items():
        # Case insensitive search for layer name
        found_layer = next((k for k in layers.keys() if k.upper() == name), None)
        if found_layer:
            layer_score += 5
            # Check color (strict check, but allow small tolerance if needed, usually exact int)
            if layers[found_layer] == color_idx:
                layer_score += 2.5
                feedback.append(f"Layer '{name}' correct (color {color_idx}).")
            else:
                feedback.append(f"Layer '{name}' found but wrong color (expected {color_idx}, got {layers[found_layer]}).")
        else:
            feedback.append(f"Missing layer: '{name}'.")
    
    score += min(30, layer_score)

    # --------------------------------------------------------------------------
    # 3. Content & Geometry Verification (30 points)
    # --------------------------------------------------------------------------
    # Text content check
    found_text = " ".join(dxf_data.get('text_content', [])).upper()
    required_terms = ["L1", "L2", "STOP", "START", "M1", "PL1", "OL", "AL1", "MOTOR"]
    
    terms_found = 0
    for term in required_terms:
        if term in found_text:
            terms_found += 1
            
    text_score = (terms_found / len(required_terms)) * 15
    score += text_score
    feedback.append(f"Found {terms_found}/{len(required_terms)} required text labels.")

    # Spatial check (Rails and Rungs)
    spatial = dxf_data.get('spatial_check', {})
    v_lines = spatial.get('vertical_lines', 0)
    h_lines = spatial.get('horizontal_lines', 0)
    
    if v_lines >= 2:
        score += 7.5
        feedback.append("Power rails detected.")
    if h_lines >= 3:
        score += 7.5
        feedback.append("Ladder rungs detected.")
        
    # --------------------------------------------------------------------------
    # 4. VLM Verification (20 points)
    # --------------------------------------------------------------------------
    # Use trajectory frames to ensure work was done in LibreCAD
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if frames and final_screen:
        prompt = (
            "Review this sequence of screenshots from LibreCAD. "
            "1. Does the final image show an electrical ladder diagram? "
            "2. Are there vertical power rails and horizontal rungs? "
            "3. Are there text labels and component symbols (circles)? "
            "Answer 'YES' if the drawing looks like a valid attempt at a ladder diagram."
        )
        
        try:
            vlm_res = query_vlm(images=frames + [final_screen], prompt=prompt)
            if vlm_res.get('success') and "YES" in vlm_res.get('parsed', {}).get('answer', '').upper():
                score += 20
                feedback.append("VLM visual verification passed.")
            else:
                score += 5 # Participation points for VLM existing
                feedback.append("VLM visual verification ambiguous.")
        except Exception:
            feedback.append("VLM verification failed to execute.")
    
    # --------------------------------------------------------------------------
    # Final Result
    # --------------------------------------------------------------------------
    passed = score >= 60
    return {
        "passed": passed,
        "score": round(score),
        "feedback": " ".join(feedback)
    }