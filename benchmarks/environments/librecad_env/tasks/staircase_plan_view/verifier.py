#!/usr/bin/env python3
"""
Verifier for staircase_plan_view task.
"""

import json
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_staircase_plan_view(traj, env_info, task_info):
    """
    Verifies the staircase plan task using:
    1. DXF analysis results (computed in container)
    2. File attributes (existence, creation time)
    3. VLM visual verification of the screenshot
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load results from container
    import tempfile
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
    feedback = []
    
    # 2. Check File Existence & Integrity (10 pts)
    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file not found"}
    
    if not result.get("file_created_during_task", False):
        feedback.append("File not created/modified during task session.")
        # We don't fail immediately but this is suspicious
    else:
        score += 10
        feedback.append("File created during task.")

    # 3. Analyze DXF Structure (60 pts)
    dxf = result.get("dxf_analysis", {})
    if not dxf.get("valid_dxf", False):
        feedback.append("File is not a valid DXF or could not be parsed.")
    else:
        # Layers (10 pts)
        layers = dxf.get("layers", [])
        required_layers = ["Treads", "Labels", "Dimensions"]
        found_layers = [l for l in required_layers if l in layers]
        if len(found_layers) == 3:
            score += 10
            feedback.append("All required layers found.")
        else:
            feedback.append(f"Missing layers. Found: {found_layers}")

        # Tread Lines (20 pts)
        # Expect ~11 horizontal lines
        h_lines = dxf.get("horizontal_lines", 0)
        if h_lines >= 9:
            score += 20
            feedback.append(f"Found {h_lines} horizontal tread lines (Target: 11).")
        elif h_lines >= 5:
            score += 10
            feedback.append(f"Found {h_lines} horizontal tread lines - partial credit.")
        else:
            feedback.append(f"Insufficient horizontal lines ({h_lines}).")

        # Geometry Correctness (10 pts)
        # Check width (~900) and spacing (~250)
        if dxf.get("correct_width_lines", 0) >= 9:
            score += 5
        if dxf.get("correct_spacing_lines", 0) >= 8:
            score += 5

        # Text/Labels (10 pts)
        text_content = " ".join(dxf.get("text_contents", [])).upper()
        digits_found = sum(1 for i in range(1, 11) if str(i) in text_content)
        if digits_found >= 8:
            score += 5
            feedback.append("Riser numbering found.")
        
        if "UP" in text_content:
            score += 5
            feedback.append("'UP' indicator found.")

        # Dimensions (10 pts)
        if dxf.get("dimensions_count", 0) >= 2:
            score += 10
            feedback.append("Dimensions found.")
        elif dxf.get("dimensions_count", 0) == 1:
            score += 5

    # 4. VLM Verification (30 pts)
    # Use trajectory to ensure work was done manually and final result looks right
    frames = sample_trajectory_frames(traj, n=3)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Review the final screenshot of a CAD drawing.
    Does it show a staircase plan view?
    
    Check for:
    1. A series of parallel horizontal lines (treads).
    2. Numbers 1-10 on the treads.
    3. An arrow or 'UP' text.
    4. Dimension lines.
    
    Return JSON: {"is_staircase": bool, "has_numbers": bool, "has_dimensions": bool}
    """
    
    vlm_result = query_vlm(images=[final_screen], prompt=vlm_prompt)
    
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("is_staircase"):
            score += 10
        if parsed.get("has_numbers"):
            score += 10
        if parsed.get("has_dimensions"):
            score += 10
    else:
        # Fallback if VLM fails: give points if DXF analysis was very strong
        if score >= 60:
            score += 20
            feedback.append("VLM skipped, bonus based on DXF quality.")

    passed = score >= 50
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }