#!/usr/bin/env python3
"""
Verifier for survey_plot_boundary task.
"""

import json
import os
import tempfile
import math
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_survey_plot(traj, env_info, task_info):
    """
    Verifies the survey plot task by checking the exported JSON analysis 
    (generated inside the container) and performing VLM validation.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Check 1: File Existence & Validity (10 pts) ---
    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    if not result.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "File timestamp indicates it was not created during this task."}
    
    dxf_data = result.get("dxf_analysis", {})
    if not dxf_data.get("valid_dxf", False):
        return {"passed": False, "score": 0, "feedback": "Output file is not a valid DXF."}
        
    score += 10
    feedback.append("Valid DXF file created.")

    # --- Check 2: Layers (20 pts) ---
    layers = dxf_data.get("layers", {})
    
    # PARCEL_BOUNDARY (Red=1)
    if "PARCEL_BOUNDARY" in layers:
        if layers["PARCEL_BOUNDARY"]["color"] == 1:
            score += 10
            feedback.append("PARCEL_BOUNDARY layer correct (Red).")
        else:
            score += 5
            feedback.append("PARCEL_BOUNDARY layer exists but wrong color.")
    else:
        feedback.append("Missing PARCEL_BOUNDARY layer.")

    # ANNOTATIONS (Green=3)
    if "ANNOTATIONS" in layers:
        if layers["ANNOTATIONS"]["color"] == 3:
            score += 10
            feedback.append("ANNOTATIONS layer correct (Green).")
        else:
            score += 5
            feedback.append("ANNOTATIONS layer exists but wrong color.")
    else:
        feedback.append("Missing ANNOTATIONS layer.")

    # --- Check 3: Polyline Geometry (30 pts) ---
    target_points = [[0,0], [50,0], [55,35], [25,45], [0,30]]
    tolerance = 2.0
    
    # Find the best matching polyline
    best_poly_score = 0
    poly_found = False
    
    for poly in dxf_data.get("polylines", []):
        current_poly_score = 0
        
        # Check Layer
        if poly["layer"] == "PARCEL_BOUNDARY":
            current_poly_score += 5
            
        # Check Closure
        if poly["closed"]:
            current_poly_score += 5
            
        # Check Vertices
        points = poly["points"]
        matches = 0
        if len(points) >= 5:
            # Simple greedy match for unordered points
            used_indices = set()
            for tp in target_points:
                for i, p in enumerate(points):
                    if i in used_indices: continue
                    dist = math.sqrt((tp[0]-p[0])**2 + (tp[1]-p[1])**2)
                    if dist <= tolerance:
                        matches += 1
                        used_indices.add(i)
                        break
        
        vertex_score = min(20, matches * 4) # 4 pts per vertex
        current_poly_score += vertex_score
        
        if current_poly_score > best_poly_score:
            best_poly_score = current_poly_score
            poly_found = True

    score += best_poly_score
    if best_poly_score >= 25:
        feedback.append("Parcel boundary geometry is correct.")
    elif poly_found:
        feedback.append(f"Parcel boundary partially correct (Score: {best_poly_score}).")
    else:
        feedback.append("No valid parcel boundary polyline found.")

    # --- Check 4: Text Annotations (20 pts) ---
    texts = dxf_data.get("texts", [])
    
    has_parcel_text = False
    has_area_text = False
    
    for t in texts:
        content = t["content"].upper()
        layer = t["layer"]
        
        if "PARCEL" in content and "2047" in content:
            if layer == "ANNOTATIONS":
                has_parcel_text = True
        
        if "2050" in content:
            if layer == "ANNOTATIONS":
                has_area_text = True

    if has_parcel_text:
        score += 10
        feedback.append("Parcel ID text correct.")
    else:
        feedback.append("Missing or incorrect Parcel ID text.")
        
    if has_area_text:
        score += 10
        feedback.append("Area text correct.")
    else:
        feedback.append("Missing or incorrect Area text.")

    # --- Check 5: VLM Verification (20 pts) ---
    # We use VLM to verify the "process" - did they actually use the UI?
    frames = sample_trajectory_frames(traj, n=4)
    final_ss = get_final_screenshot(traj)
    
    vlm_prompt = """
    Review this sequence of screenshots from a CAD session.
    The user should be:
    1. Drawing a specific shape (polygon).
    2. Creating layers (looking for Layer Settings or Layer List usage).
    3. Adding text annotations.
    
    Does the final result show a polygon with text inside it?
    Do the trajectory frames show active work in LibreCAD?
    Answer 'YES' or 'NO' and provide a confidence score (0-10).
    """
    
    vlm_result = query_vlm(images=frames + [final_ss], prompt=vlm_prompt)
    
    vlm_score = 0
    if "YES" in vlm_result.get("result", "").upper():
        vlm_score = 20
        feedback.append("VLM confirms visual correctness.")
    else:
        feedback.append("VLM visual check failed or inconclusive.")
        # Fallback: if program check was perfect, give partial VLM credit
        if score >= 70:
            vlm_score = 10
            
    score += vlm_score

    # Final result
    passed = score >= 60 and result.get("file_exists", False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }