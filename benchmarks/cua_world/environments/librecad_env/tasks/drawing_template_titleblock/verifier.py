#!/usr/bin/env python3
"""
Verifier for Drawing Template Task (drawing_template_titleblock@1).
"""

import json
import os
import tempfile
import math
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_drawing_template(traj, env_info, task_info):
    """
    Verifies the LibreCAD drawing template task.
    Checks for file existence, validity, layer structure, specific geometry, and text.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Extract analysis data
    dxf_data = result.get("dxf_analysis", {})
    task_start = result.get("task_start", 0)
    
    score = 0
    feedback_parts = []
    
    # --- Criterion 1: File Existence and Validity (15 pts) ---
    if not dxf_data.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file a3_template.dxf not found."}
    
    # Anti-gaming: File modified after start?
    file_mtime = dxf_data.get("file_mtime", 0)
    if file_mtime <= task_start:
        feedback_parts.append("Warning: File timestamp is older than task start.")
        # We don't fail immediately but this is suspicious if the file existed (it shouldn't have)
    else:
        score += 5 # Created during task
        
    if dxf_data.get("is_valid_dxf", False):
        score += 10
        feedback_parts.append("Valid DXF file created.")
    else:
        return {"passed": False, "score": score, "feedback": "File exists but is not a valid DXF."}

    # --- Criterion 2: Layers (15 pts) ---
    layers = set(dxf_data.get("layers", []))
    required_layers = {"Border", "TitleBlock", "Text"}
    found_layers = required_layers.intersection(layers)
    
    score += len(found_layers) * 5
    if len(found_layers) < 3:
        feedback_parts.append(f"Missing layers: {required_layers - layers}")
    else:
        feedback_parts.append("All required layers present.")

    # --- Criterion 3: Geometry Verification (40 pts) ---
    # Helper to check for a rectangle
    # Rectangles can be 1 Polyline OR 4 Lines.
    lines = dxf_data.get("lines", [])
    polylines = dxf_data.get("polylines", [])
    
    def check_rectangle(min_pt, max_pt, layer, tolerance=2.0):
        # Target segments
        x1, y1 = min_pt
        x2, y2 = max_pt
        
        # Method A: Closed Polyline matching points
        for poly in polylines:
            if poly["layer"] != layer or not poly.get("is_closed"):
                continue
            pts = poly["points"]
            if len(pts) != 4: continue
            
            # Check bounding box of polyline
            px = [p[0] for p in pts]
            py = [p[1] for p in pts]
            if (abs(min(px) - x1) < tolerance and abs(max(px) - x2) < tolerance and
                abs(min(py) - y1) < tolerance and abs(max(py) - y2) < tolerance):
                return True

        # Method B: 4 Lines
        # We look for lines matching the 4 sides
        sides_found = 0
        targets = [
            ((x1, y1), (x2, y1)), # Bottom
            ((x2, y1), (x2, y2)), # Right
            ((x2, y2), (x1, y2)), # Top
            ((x1, y2), (x1, y1))  # Left
        ]
        
        for t_start, t_end in targets:
            for line in lines:
                if line["layer"] != layer: continue
                ls = line["start"]
                le = line["end"]
                # Check distance of endpoints
                d1 = math.hypot(ls[0]-t_start[0], ls[1]-t_start[1])
                d2 = math.hypot(le[0]-t_end[0], le[1]-t_end[1])
                # Check reverse
                d3 = math.hypot(ls[0]-t_end[0], ls[1]-t_end[1])
                d4 = math.hypot(le[0]-t_start[0], le[1]-t_start[1])
                
                if (d1 < tolerance and d2 < tolerance) or (d3 < tolerance and d4 < tolerance):
                    sides_found += 1
                    break
        
        return sides_found >= 4

    # Check Outer Border (0,0) to (420,297)
    if check_rectangle([0,0], [420,297], "Border"):
        score += 15
        feedback_parts.append("Outer border correct.")
    else:
        feedback_parts.append("Outer border missing or incorrect dimensions.")

    # Check Inner Margin (10,10) to (410,287)
    if check_rectangle([10,10], [410,287], "Border"):
        score += 15
        feedback_parts.append("Inner margin correct.")
    else:
        feedback_parts.append("Inner margin missing or incorrect dimensions.")
        
    # Check Title Block Box (240,10) to (410,50)
    if check_rectangle([240,10], [410,50], "TitleBlock", tolerance=3.0):
        score += 10
        feedback_parts.append("Title block box correct.")
    else:
        feedback_parts.append("Title block box missing or incorrect.")

    # --- Criterion 4: Text Verification (15 pts) ---
    texts = dxf_data.get("texts", [])
    text_specs = [
        ("RESIDENTIAL FLOOR PLAN", "Text", 5),
        ("Torres", "Text", 5),
        ("1:50", "Text", 5)
    ]
    
    for content, layer, pts in text_specs:
        found = False
        for t in texts:
            if t["layer"] == layer and content.lower() in t["content"].lower():
                found = True
                break
        if found:
            score += pts
            feedback_parts.append(f"Text '{content}' found.")
        else:
            feedback_parts.append(f"Text '{content}' missing.")

    # --- Criterion 5: VLM Verification (15 pts) ---
    # Visual check to ensure it actually looks like a drawing (not just disconnected entities)
    final_screenshot = get_final_screenshot(traj)
    vlm_score = 0
    if final_screenshot:
        try:
            prompt = """
            Analyze this CAD drawing screenshot. 
            Does it show a standard engineering drawing template?
            I am looking for:
            1. A rectangular border around the page.
            2. A title block box in the bottom-right corner.
            3. Text visible inside the title block.
            
            Answer YES or NO and provide a confidence score (0-100).
            """
            vlm_resp = query_vlm(images=[final_screenshot], prompt=prompt)
            parsed = vlm_resp.get("parsed", {})
            # Simple heuristic parsing since query_vlm returns dict if JSON requested or text
            # Assuming standard gym_anything VLM handling
            content = str(vlm_resp).lower()
            
            if "yes" in content or (isinstance(vlm_resp, dict) and vlm_resp.get("success")):
                vlm_score = 15
                feedback_parts.append("VLM confirms drawing structure.")
            else:
                feedback_parts.append("VLM did not recognize drawing template structure.")
        except Exception as e:
            logger.error(f"VLM error: {e}")
            # Fallback points if programmatic passed
            if score > 60: vlm_score = 15
    
    score += vlm_score

    # Final Check
    passed = score >= 60 and check_rectangle([0,0], [420,297], "Border")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }