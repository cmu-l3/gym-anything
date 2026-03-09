#!/usr/bin/env python3
"""
Verifier for nameplate_template@1 task.
Analyzes the JSON output from the container (which includes pre-parsed DXF data)
and performs VLM visual verification.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_nameplate_template(traj, env_info, task_info):
    """
    Verifies the nameplate template task.
    
    Scoring Breakdown (100 pts total):
    - 5 pts: File exists and is valid DXF
    - 5 pts: Anti-gaming (created during task, not empty)
    - 24 pts: Layers correct (BORDER=7, HOLES=2, TEXT=4)
    - 24 pts: Rectangles correct (Outer 120x60, Inner 110x50)
    - 16 pts: Holes correct (2 holes, r=2, correct pos)
    - 16 pts: Text content correct
    - 10 pts: VLM Visual Verification
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
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

    score = 0
    feedback = []
    dxf_data = result.get('dxf_analysis', {})
    
    # --- Criterion 1: File Validity (5 pts) ---
    if result.get('file_exists') and dxf_data.get('valid_dxf'):
        score += 5
        feedback.append("Valid DXF file found.")
    else:
        return {"passed": False, "score": 0, "feedback": "No valid DXF file found."}

    # --- Criterion 2: Anti-Gaming (5 pts) ---
    if result.get('file_created_during_task') and dxf_data.get('entity_count', 0) > 5:
        score += 5
    else:
        feedback.append("Warning: File checks failed (timestamp or empty file).")

    # --- Criterion 3: Layers (24 pts) ---
    # Specs: BORDER=7 (White), HOLES=2 (Yellow), TEXT=4 (Cyan)
    layers = dxf_data.get('layers', {})
    expected_layers = metadata.get('layer_specs', {"BORDER": 7, "HOLES": 2, "TEXT": 4})
    
    for name, color in expected_layers.items():
        if name in layers:
            if layers[name] == color:
                score += 8
                feedback.append(f"Layer {name} correct.")
            else:
                score += 4
                feedback.append(f"Layer {name} exists but wrong color ({layers[name]}).")
        else:
            feedback.append(f"Layer {name} missing.")

    # --- Criterion 4: Rectangles (24 pts) ---
    # Need to reconstruct bounding boxes from line segments or polylines
    # This is simplified; a full geometric solver is complex.
    # We look for rough extents of entities on the BORDER layer.
    
    rect_entities = [r for r in dxf_data.get('rectangles', []) if r['layer'] == 'BORDER']
    
    # Collect all points
    all_points = []
    for r in rect_entities:
        for p in r['points']:
            all_points.append(p)
            
    if all_points:
        xs = [p[0] for p in all_points]
        ys = [p[1] for p in all_points]
        min_x, max_x = min(xs), max(xs)
        min_y, max_y = min(ys), max(ys)
        
        # Check outer: 0,0 to 120,60
        if abs(min_x - 0) < 1 and abs(min_y - 0) < 1 and abs(max_x - 120) < 1 and abs(max_y - 60) < 1:
            score += 12
            feedback.append("Outer border dimensions correct.")
        elif abs(max_x - min_x - 120) < 2 and abs(max_y - min_y - 60) < 2:
            score += 6
            feedback.append("Outer border size correct, but position offset.")
            
        # Check inner is harder without separating entities, but we check existence of points near 5,5
        has_inner_min = any(abs(x - 5) < 1 for x in xs) and any(abs(y - 5) < 1 for y in ys)
        has_inner_max = any(abs(x - 115) < 1 for x in xs) and any(abs(y - 55) < 1 for y in ys)
        
        if has_inner_min and has_inner_max:
            score += 12
            feedback.append("Inner border geometry detected.")
    else:
        feedback.append("No geometry found on BORDER layer.")

    # --- Criterion 5: Holes (16 pts) ---
    circles = [c for c in dxf_data.get('circles', []) if c['layer'] == 'HOLES']
    
    # Check Left Hole (10, 30)
    left_hole = any(abs(c['center'][0] - 10) < 2 and abs(c['center'][1] - 30) < 2 and abs(c['radius'] - 2) < 0.5 for c in circles)
    if left_hole:
        score += 8
        feedback.append("Left mounting hole correct.")
        
    # Check Right Hole (110, 30)
    right_hole = any(abs(c['center'][0] - 110) < 2 and abs(c['center'][1] - 30) < 2 and abs(c['radius'] - 2) < 0.5 for c in circles)
    if right_hole:
        score += 8
        feedback.append("Right mounting hole correct.")

    # --- Criterion 6: Text (16 pts) ---
    text_entities = [t for t in dxf_data.get('texts', []) if t['layer'] == 'TEXT']
    all_text_content = " ".join([t['content'].upper() for t in text_entities])
    
    required_keywords = ["MODEL", "SERIAL", "WEIGHT", "DATE"]
    for kw in required_keywords:
        if kw in all_text_content:
            score += 4
            feedback.append(f"Text '{kw}' found.")
        else:
            feedback.append(f"Text '{kw}' missing.")

    # --- Criterion 7: VLM Visual Verification (10 pts) ---
    # Use VLM to confirm the drawing looks like a nameplate
    vlm_prompt = """
    Analyze this CAD drawing screenshot.
    Does it look like a mechanical nameplate or label template?
    I expect to see:
    1. A rectangular border.
    2. Two small holes (circles) on the sides.
    3. Text fields like 'MODEL', 'SERIAL', 'WEIGHT'.
    
    Respond with JSON: {"looks_correct": boolean, "confidence": number}
    """
    
    frames = sample_trajectory_frames(traj, n=3)
    final_screen = get_final_screenshot(traj)
    
    if final_screen:
        try:
            # We prioritize the final screenshot for the static drawing result
            vlm_response = query_vlm(prompt=vlm_prompt, image=final_screen)
            parsed = vlm_response.get("parsed", {})
            
            if parsed.get("looks_correct", False):
                score += 10
                feedback.append("VLM confirms drawing appearance.")
            else:
                feedback.append("VLM did not recognize valid nameplate geometry.")
        except Exception as e:
            feedback.append(f"VLM check failed: {e}")
            # Fallback points if programmatic checks were strong
            if score > 60:
                score += 10
    
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }