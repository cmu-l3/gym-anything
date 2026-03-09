#!/usr/bin/env python3
import json
import os
import tempfile
from gym_anything.vlm import query_vlm, get_final_screenshot

def verify_stone_countertop(traj, env_info, task_info):
    """
    Verifies the Stone Countertop Fabrication task.
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
    file_exists = result.get("file_exists", False)
    created_during = result.get("file_created_during_task", False)
    analysis = result.get("dxf_analysis", {})
    
    score = 0
    feedback = []
    
    # 3. Scoring Criteria (Programmatic)
    
    # Criterion 1: File Creation (10 pts)
    if file_exists and created_during:
        score += 10
        feedback.append("DXF file created successfully.")
    elif file_exists:
        score += 5
        feedback.append("DXF file exists but timestamp check failed (pre-existing?).")
    else:
        feedback.append("DXF file not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: Layers (10 pts)
    layers = analysis.get("layers", {})
    stone_layer = "STONE" in layers
    cutouts_layer = "CUTOUTS" in layers
    
    # Check colors roughly (Cyan=4, Red=1)
    stone_color = layers.get("STONE", -1)
    cutouts_color = layers.get("CUTOUTS", -1)
    
    if stone_layer and cutouts_layer:
        if stone_color == 4 and cutouts_color == 1:
            score += 10
            feedback.append("Layers 'STONE' (Cyan) and 'CUTOUTS' (Red) correct.")
        else:
            score += 5
            feedback.append("Layers exist but colors might be incorrect.")
    else:
        feedback.append(f"Missing layers. Found: {list(layers.keys())}")

    # Criterion 3: L-Shape Geometry (30 pts)
    stone_geom = analysis.get("stone_geometry", {})
    if stone_geom.get("valid_bbox", False):
        score += 30
        feedback.append("L-shaped profile dimensions correct (3000x2400).")
    else:
        feedback.append("Outer profile dimensions are incorrect.")

    # Criterion 4: Fillet (20 pts)
    if stone_geom.get("has_fillet", False):
        score += 20
        feedback.append("Internal corner fillet (R=50) detected.")
    else:
        feedback.append("Internal corner fillet missing or incorrect radius.")

    # Criterion 5: Cutouts (30 pts)
    cutouts = analysis.get("cutouts", {})
    if cutouts.get("sink_found", False):
        score += 15
        feedback.append("Sink cutout correctly positioned and sized.")
    else:
        feedback.append("Sink cutout missing or incorrect.")
        
    if cutouts.get("cooktop_found", False):
        score += 15
        feedback.append("Cooktop cutout correctly positioned and sized.")
    else:
        feedback.append("Cooktop cutout missing or incorrect.")

    # 4. Secondary Verification (VLM) for sanity check
    # Only run if we have a basic score to confirm it's not just a programmed invisible file
    if score >= 50:
        final_screenshot = get_final_screenshot(traj)
        if final_screenshot:
            vlm_res = query_vlm(
                prompt="Is this a CAD drawing showing an L-shaped counter? Do you see a cyan outline and red internal rectangles?",
                image=final_screenshot
            )
            if vlm_res.get("parsed", {}).get("answer", False) or "yes" in vlm_res.get("response", "").lower():
                # VLM confirms visual appearance
                pass 
            else:
                feedback.append("(VLM could not visually confirm the drawing geometry)")
    
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }