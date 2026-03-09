#!/usr/bin/env python3
"""
Verifier for truss_bridge_elevation task.
Reads the JSON analysis produced by the container script.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_truss_bridge_elevation(traj, env_info, task_info):
    """
    Verify the Warren Truss Elevation drawing.
    
    Scoring Breakdown (100 pts):
    - File validity & Setup (10 pts)
    - Layers (10 pts)
    - Geometric Structure (40 pts)
    - Annotations & Dimensions (20 pts)
    - VLM Visual Verification (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    max_score = 100
    
    # 1. Read Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Analysis Data
    analysis = result.get("analysis", {})
    file_created = result.get("file_created_during_task", False)
    valid_dxf = analysis.get("valid_dxf", False)
    
    # --- CRITERION 1: File Existence & Validity (10 pts) ---
    if file_created and valid_dxf:
        score += 10
        feedback_parts.append("DXF file created and valid")
    elif not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "No output file found"}
    else:
        feedback_parts.append("File exists but invalid or pre-dated")

    # --- CRITERION 2: Layers (10 pts) ---
    layers = analysis.get("layers", [])
    required_layers = ["chords", "webs", "dimensions", "labels"]
    layers_found = [l for l in required_layers if l in layers]
    
    layer_score = 0
    if len(layers_found) == 4:
        layer_score = 10
    else:
        layer_score = len(layers_found) * 2
    
    score += layer_score
    if layer_score < 10:
        feedback_parts.append(f"Missing layers: {set(required_layers) - set(layers_found)}")
    else:
        feedback_parts.append("All layers present")

    # --- CRITERION 3: Geometry (40 pts) ---
    geo = analysis.get("geometry", {})
    geo_score = 0
    
    if geo.get("bottom_chord"): geo_score += 10
    if geo.get("top_chord"): geo_score += 10
    
    # Vertical ends (expect 2)
    ends = geo.get("vertical_ends", 0)
    if ends >= 2: geo_score += 5
    
    # Diagonals (expect at least 6 for Warren truss)
    diags = geo.get("diagonals", 0)
    if diags >= 6: 
        geo_score += 15
    elif diags > 0:
        geo_score += 5
        
    score += geo_score
    feedback_parts.append(f"Geometry score: {geo_score}/40 (Diagonals: {diags})")

    # --- CRITERION 4: Content & Annotations (20 pts) ---
    content = analysis.get("content", {})
    ents = analysis.get("entities", {})
    
    # Dimensions (expect > 0)
    if ents.get("dimensions", 0) >= 2:
        score += 5
        feedback_parts.append("Dimensions found")
    
    # Text Content
    text_score = 0
    if content.get("has_title"): text_score += 5
    if content.get("has_scale"): text_score += 3
    if content.get("has_pin_label") or content.get("has_roller_label"): text_score += 7
    
    score += text_score
    feedback_parts.append(f"Annotation score: {text_score + (5 if ents.get('dimensions', 0) >= 2 else 0)}/20")

    # --- CRITERION 5: VLM Verification (20 pts) ---
    # Using VLM to verify the visual structure (triangles, truss shape)
    # This catches "correct entities but wrong arrangement"
    final_screenshot = get_final_screenshot(traj)
    vlm_score = 0
    
    if final_screenshot:
        prompt = """
        Analyze this CAD drawing of a bridge truss.
        1. Do you see a truss structure with triangular/diagonal webs?
        2. Are there dimension lines visible?
        3. Is there text labeling the drawing?
        4. Does it look like a complete elevation view?
        
        Respond with JSON: {"is_truss": bool, "has_dims": bool, "has_text": bool, "complete": bool}
        """
        
        try:
            vlm_res = query_vlm(images=[final_screenshot], prompt=prompt)
            parsed = vlm_res.get("parsed", {})
            
            if parsed.get("is_truss"): vlm_score += 10
            if parsed.get("has_dims"): vlm_score += 3
            if parsed.get("has_text"): vlm_score += 2
            if parsed.get("complete"): vlm_score += 5
            
            feedback_parts.append(f"Visual check: {vlm_score}/20")
        except Exception:
            feedback_parts.append("Visual check failed (VLM error)")
            # Fallback: if geometry score is high, give partial credit
            if geo_score >= 30: vlm_score = 10
            
    score += vlm_score

    # Final Result
    passed = score >= 60 and valid_dxf
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }