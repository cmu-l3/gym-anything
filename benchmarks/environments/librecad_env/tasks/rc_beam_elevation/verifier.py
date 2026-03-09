#!/usr/bin/env python3
"""
Verifier for rc_beam_elevation task.
Uses the JSON output from the container's internal DXF analysis.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rc_beam_elevation(traj, env_info, task_info):
    """
    Verify RC Beam Elevation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON from container
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

    # 2. Extract Data
    dxf = result.get('dxf_analysis', {})
    file_created = result.get('file_created_during_task', False)
    
    score = 0
    feedback = []
    
    # CRITERION 1: File Creation (10 pts)
    if file_created:
        score += 10
        feedback.append("DXF file created.")
    else:
        feedback.append("DXF file NOT created.")
        return {"passed": False, "score": 0, "feedback": "No output file found."}

    # CRITERION 2: DXF Validity (5 pts)
    if dxf.get('valid_dxf'):
        score += 5
    else:
        feedback.append("Invalid DXF format.")
        return {"passed": False, "score": score, "feedback": "Invalid DXF file."}

    # CRITERION 3: Layers (10 pts)
    layers = dxf.get('layers', [])
    required_layers = ['CONCRETE', 'REBAR_MAIN', 'REBAR_STIRRUPS']
    missing_layers = [l for l in required_layers if l not in layers]
    
    if not missing_layers:
        score += 10
        feedback.append("All required layers present.")
    else:
        feedback.append(f"Missing layers: {missing_layers}")
        # Partial credit
        if len(missing_layers) < 3:
            score += 5

    # CRITERION 4: Beam Geometry (15 pts)
    # Expecting 5000 x 600
    bounds = dxf.get('concrete_bounds', {})
    if bounds:
        width = bounds.get('width', 0)
        height = bounds.get('height', 0)
        
        # Tolerance +/- 100mm
        if 4900 <= width <= 5100 and 500 <= height <= 700:
            score += 15
            feedback.append(f"Beam geometry correct ({width:.0f}x{height:.0f}).")
        else:
            feedback.append(f"Beam geometry incorrect (Got {width:.0f}x{height:.0f}, expected 5000x600).")
    else:
        feedback.append("No concrete geometry found.")

    # CRITERION 5: Main Rebar Cover (20 pts)
    # Expecting Y coords near 40 and 560 (assuming beam at 0,0)
    # OR relative distance between bars = 520 (600 - 40 - 40)
    rebar_ys = dxf.get('rebar_y_coords', [])
    if len(rebar_ys) >= 2:
        # Check range/distance
        min_y = min(rebar_ys)
        max_y = max(rebar_ys)
        dist = max_y - min_y
        
        # Expected distance: 520mm +/- 20mm
        if 500 <= dist <= 540:
            score += 20
            feedback.append("Main rebar placement/cover correct.")
        else:
            feedback.append(f"Main rebar spacing incorrect (Dist: {dist}, Expected ~520).")
            score += 5  # Points for having rebar lines at all
    else:
        feedback.append("Insufficient main rebar lines found.")

    # CRITERION 6: Stirrup Spacing & Count (20 pts)
    median_spacing = dxf.get('stirrup_spacing_median', 0)
    stirrup_count = dxf.get('stirrup_count', 0)
    
    # Expected spacing 200 +/- 10
    if 190 <= median_spacing <= 210:
        score += 15
        feedback.append(f"Stirrup spacing correct ({median_spacing:.1f}mm).")
    else:
        feedback.append(f"Stirrup spacing incorrect (Got {median_spacing:.1f}, Expected 200).")
        
    # Expected count ~25 (20-30 is safe)
    if 20 <= stirrup_count <= 30:
        score += 5
        feedback.append(f"Stirrup count correct ({stirrup_count}).")

    # CRITERION 7: VLM Verification (20 pts)
    # Check if the final image actually looks like a technical drawing
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        vlm_prompt = "Is this a technical CAD drawing showing a rectangular beam with internal reinforcement lines? Respond with YES or NO and a brief reason."
        vlm_res = query_vlm(vlm_prompt, final_screenshot)
        
        if vlm_res.get("success"):
            content = vlm_res.get("content", "").lower()
            if "yes" in content:
                score += 20
                feedback.append("VLM confirms drawing appearance.")
            else:
                feedback.append("VLM did not recognize drawing.")
    else:
        feedback.append("No screenshot available for VLM.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }